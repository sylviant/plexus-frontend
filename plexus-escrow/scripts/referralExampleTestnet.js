// The Correction Plan's own example (task 2.5 / 2.8) on the real chain, with fresh wallets:
// a $100 product + $15 delivery bought with a referrer gives: seller $113, referrer $0.60, buyer cashback $0.40, PLEXUS $1.00.
//   npx hardhat run scripts/referralExampleTestnet.js --network bscTestnet
// Needs the deployer to be the operator (it signs the quote).
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");
const { useFixedGasPrice } = require("./lib/gas");

const E = (n) => ethers.parseEther(String(n));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const QUOTE_TYPES = {
  Quote: [
    { name: "orderRef", type: "bytes32" }, { name: "buyer", type: "address" }, { name: "seller", type: "address" },
    { name: "referrer", type: "address" }, { name: "productAmount", type: "uint256" }, { name: "deliveryAmount", type: "uint256" },
    { name: "feeBps", type: "uint16" }, { name: "international", type: "bool" }, { name: "validUntil", type: "uint256" },
  ],
};

async function main() {
  const dep = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "deployments", `${network.name}.json`), "utf8"));
  const [deployer] = await ethers.getSigners();
  if (deployer.address.toLowerCase() !== dep.operator.toLowerCase()) throw new Error("the deployer key must be the operator");
  const provider = ethers.provider;
  useFixedGasPrice(provider);
  const escrow = await ethers.getContractAt("PlexusEscrowV2", dep.escrow);
  const token = await ethers.getContractAt("MockUSDT", dep.token);
  const tx = async (p) => { const rc = await (await p).wait(); await sleep(3000); return rc; };
  const until = async (read, expected, label) => {
    for (let i = 0; i < 15; i++) { const v = await read(); if (v === expected) return v; await sleep(2000); }
    throw new Error(`${label}: never reached ${expected}`);
  };

  const buyer = ethers.Wallet.createRandom().connect(provider);
  const seller = ethers.Wallet.createRandom().connect(provider);
  const referrer = ethers.Wallet.createRandom(); // never transacts: only its credited reward is read
  console.log("buyer   ", buyer.address, "\nseller  ", seller.address, "\nreferrer", referrer.address);

  await tx(deployer.sendTransaction({ to: buyer.address, value: ethers.parseEther("0.008") }));
  await tx(deployer.sendTransaction({ to: seller.address, value: ethers.parseEther("0.004") }));
  await tx(token.mint(buyer.address, E(200)));
  await tx(token.connect(buyer).approve(dep.escrow, E(115))); // exactly the order total

  const treasury = dep.treasury;
  const treasuryBefore = await escrow.balances(treasury);
  const fee = Number((await escrow.feeConfig()).feeBps);
  const q = {
    orderRef: ethers.id(`referral-example-${Date.now()}`), buyer: buyer.address, seller: seller.address, referrer: referrer.address,
    productAmount: E(100), deliveryAmount: E(15), feeBps: fee, international: false,
    validUntil: (await provider.getBlock("latest")).timestamp + 3600,
  };
  const domain = { name: "PlexusEscrow", version: "2", chainId: (await provider.getNetwork()).chainId, verifyingContract: dep.escrow };
  const sig = await deployer.signTypedData(domain, QUOTE_TYPES, q);
  await tx(escrow.connect(buyer).createOrder(q, sig));
  console.log("order paid: $100 product + $15 delivery, referrer set");

  await until(async () => (await escrow.getOrder(q.orderRef)).paidAt > 0n, true, "order visible");
  const paidAt = (await escrow.getOrder(q.orderRef)).paidAt;
  await tx(escrow.connect(seller).markShipped(q.orderRef, ethers.id("DHL"), ethers.id("TRACK"), ethers.id("proof"), paidAt));
  await tx(escrow.connect(buyer).confirmReceipt(q.orderRef));

  const expected = { seller: E(113), referrer: E("0.6"), buyerCashback: E("0.4"), plexus: E(1) };
  const got = {
    seller: await until(() => escrow.balances(seller.address).then((x) => x.toString()), expected.seller.toString(), "seller credit").then(BigInt),
    referrer: await escrow.rewards(referrer.address),
    buyerCashback: await escrow.rewards(buyer.address),
    plexus: (await escrow.balances(treasury)) - treasuryBefore,
  };
  const rows = [["seller (product - 2% + delivery)", got.seller, expected.seller], ["referrer (30% of the 2.00 commission)", got.referrer, expected.referrer],
    ["buyer cashback (20% of the commission)", got.buyerCashback, expected.buyerCashback], ["PLEXUS (the remaining 50%)", got.plexus, expected.plexus]];
  let ok = true;
  for (const [label, g, x] of rows) {
    const match = g === x;
    ok = ok && match;
    console.log(`${match ? "OK  " : "FAIL"} ${label.padEnd(42)} got ${ethers.formatEther(g).padStart(8)} USDT, expected ${ethers.formatEther(x)}`);
  }
  const total = got.seller + got.referrer + got.buyerCashback + got.plexus;
  console.log(`${total === E(115) ? "OK  " : "FAIL"} every cent accounted for: ${ethers.formatEther(total)} of 115.0 paid`);
  ok = ok && total === E(115);
  console.log(`order status: ${["None", "Paid", "AdjustmentProposed", "Shipped", "Disputed", "Completed"][Number((await escrow.getOrder(q.orderRef)).status)]}`);

  fs.writeFileSync(path.join(__dirname, "..", "audit", `referral-example-${network.name}.json`), JSON.stringify({
    ranAt: new Date().toISOString(), contract: dep.escrow, orderRef: q.orderRef, passed: ok,
    expected: Object.fromEntries(Object.entries(expected).map(([k, v]) => [k, ethers.formatEther(v)])),
    got: Object.fromEntries(Object.entries(got).map(([k, v]) => [k, ethers.formatEther(v)])),
  }, null, 2));
  if (!ok) process.exitCode = 1;
}

main().catch((e) => { console.error(e.shortMessage || e.message); process.exitCode = 1; });
