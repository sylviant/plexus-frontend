// End-to-end smoke test against a deployed PlexusEscrowV2 (+ MockUSDT).
//   local:   npx hardhat run scripts/smokeV2.js
//   testnet: npx hardhat run scripts/smokeV2.js --network bscTestnet
// Testnet requirement: the deployer key must also be the contract's operator
// (it signs quotes). Buyer and seller are throwaway wallets funded by the deployer.
//
// Public RPCs sit behind load balancers, so a node can lag a block behind the one that mined our
// transaction. Therefore: every write is followed by a short pause, and every check retries its read.
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");
const { deployAll } = require("./lib/deployV2");
const { useFixedGasPrice } = require("./lib/gas");

const E = (n) => ethers.parseEther(String(n));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ok = (m) => console.log(`  OK ${m}`);
let LOCAL = false;

// check(read, expected, label): `read` is a function so it can be repeated until the node catches up
async function check(read, expected, label) {
  let got;
  for (let i = 0; i < 15; i++) {
    got = await read();
    if (String(got) === String(expected)) return ok(label);
    if (LOCAL) break;
    await sleep(2000);
  }
  throw new Error(`FAIL ${label}: got ${got}, expected ${expected}`);
}
// tx(promise): wait for the receipt, then give the public RPC time to propagate the new block
async function tx(p) {
  const rc = await (await p).wait();
  if (!LOCAL) await sleep(3000);
  return rc;
}

async function main() {
  LOCAL = network.name === "hardhat";
  const local = LOCAL;
  const [deployer] = await ethers.getSigners();
  let info, operator;

  if (local) {
    info = await deployAll();
    operator = info._localSigners.s1; // operator role on local deploy
  } else {
    const file = path.join(__dirname, "..", "deployments", `${network.name}.json`);
    info = JSON.parse(fs.readFileSync(file, "utf8"));
    if (deployer.address.toLowerCase() !== info.operator.toLowerCase())
      throw new Error("Smoke test needs OPERATOR_ADDRESS == deployer so it can sign quotes.");
    if (!info.mockDeployed) throw new Error("Smoke test needs MockUSDT (it mints test funds).");
    operator = deployer;
  }

  const token = await ethers.getContractAt("MockUSDT", info.token);
  const escrow = await ethers.getContractAt("PlexusEscrowV2", info.escrow);
  const escrowAddr = info.escrow;
  const chainId = (await ethers.provider.getNetwork()).chainId;
  const provider = ethers.provider;
  if (!local) useFixedGasPrice(provider); // throwaway wallets must not use the node's (sometimes too low) fee tip

  const buyer = ethers.Wallet.createRandom().connect(provider);
  const seller = ethers.Wallet.createRandom().connect(provider);
  console.log(`\nBuyer:  ${buyer.address}\nSeller: ${seller.address}`);

  const gas = ethers.parseEther(local ? "1" : "0.01");
  for (const w of [buyer, seller]) await tx(deployer.sendTransaction({ to: w.address, value: gas }));
  await tx(token.mint(buyer.address, E(1000)));
  await tx(token.connect(buyer).approve(escrowAddr, ethers.MaxUint256));
  ok("wallets funded, USDT minted + approved");

  const domain = { name: "PlexusEscrow", version: "2", chainId, verifyingContract: escrowAddr };
  const types = {
    Quote: [
      { name: "orderRef", type: "bytes32" }, { name: "buyer", type: "address" }, { name: "seller", type: "address" },
      { name: "referrer", type: "address" }, { name: "productAmount", type: "uint256" },
      { name: "deliveryAmount", type: "uint256" }, { name: "feeBps", type: "uint16" },
      { name: "international", type: "bool" }, { name: "validUntil", type: "uint256" },
    ],
  };
  const latest = async () => (await provider.getBlock("latest")).timestamp;

  async function newOrder(tag, product, delivery) {
    const q = {
      orderRef: ethers.id(`${tag}-${Date.now()}`), buyer: buyer.address, seller: seller.address,
      referrer: ethers.ZeroAddress, productAmount: E(product), deliveryAmount: E(delivery),
      feeBps: info.feeBps, international: false, validUntil: (await latest()) + 3600,
    };
    const sig = await operator.signTypedData(domain, types, q);
    await tx(escrow.connect(buyer).createOrder(q, sig));
    return q.orderRef;
  }
  // Use the order's own payment time as the shipping date: it is always valid, whereas the chain tip can
  // be ahead of the (load-balanced) node that estimates gas, which then rejects a "future" date.
  async function paidAt(r) {
    for (let i = 0; i < 15; i++) {
      const v = (await escrow.getOrder(r)).paidAt;
      if (v > 0n) return v;
      if (LOCAL) break;
      await sleep(2000);
    }
    throw new Error("order not visible on the node");
  }
  const ship = async (r) =>
    tx(escrow.connect(seller).markShipped(r, ethers.id("DHL"), ethers.id("TRK"), ethers.id("proof"), await paidAt(r)));

  console.log("\nFlow 1: pay -> ship -> confirm -> seller withdraws");
  const heldBefore = await escrow.totalHeld(); // the contract may hold money from earlier runs
  let r = await newOrder("happy", 100, 10);
  await check(async () => (await escrow.totalHeld()) - heldBefore, E(110), "escrow holds 110 more");
  await ship(r);
  await tx(escrow.connect(buyer).confirmReceipt(r));
  await check(() => escrow.balances(seller.address), E(108), "seller credited 108 (2% commission taken)");
  await tx(escrow.connect(seller).withdraw());
  await check(() => token.balanceOf(seller.address), E(108), "seller received 108 USDT");

  console.log("\nFlow 2: pay -> seller cancels -> buyer withdraws refund");
  r = await newOrder("cancel", 50, 5);
  await tx(escrow.connect(seller).cancelBySeller(r));
  await tx(escrow.connect(buyer).withdrawRefund());
  await check(() => token.balanceOf(buyer.address), E(1000) - E(110), "buyer back to 1000 - 110 (refund of 55 received)");

  console.log("\nFlow 3: pay -> ship -> dispute -> buyer withdraws dispute");
  r = await newOrder("dispute", 20, 2);
  await ship(r);
  await tx(escrow.connect(buyer).openDispute(r, ethers.id("not received")));
  await check(async () => Number((await escrow.getOrder(r)).status), 4, "order is Disputed");
  await tx(escrow.connect(buyer).withdrawDispute(r));
  await check(async () => Number((await escrow.getOrder(r)).status), 5, "dispute withdrawn -> Completed");

  console.log("\nAll smoke checks passed.");
  if (!local) console.log(`BscScan: https://testnet.bscscan.com/address/${escrowAddr}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
