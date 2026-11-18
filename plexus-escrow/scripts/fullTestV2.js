// Full functional test of PlexusEscrowV2 on a real chain (or the local hardhat chain).
//   local:   npx hardhat run scripts/fullTestV2.js
//   testnet: npx hardhat run scripts/fullTestV2.js --network bscTestnet
//
// Needs, on testnet: deployments/bscTestnet.json (from deployV2.js), MockUSDT deployed by it,
// and the deployer key to be BOTH the contract owner and operator.
// Optional: TREASURY_PRIVATE_KEY lets the script also withdraw the treasury's fees.
//
// Not covered here because they need days of waiting (covered by test/PlexusEscrowV2.test.js
// with time travel): release(), refundUnshipped(), expireDeliveryAdjustment(),
// resolveExpiredDispute(), finalizeReturn(), executeFeeConfig().
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");
const { deployAll } = require("./lib/deployV2");
const { useFixedGasPrice } = require("./lib/gas");

const E = (n) => ethers.parseEther(String(n));
const H = (s) => ethers.id(s);
const ZERO = ethers.ZeroAddress;
const Reason = { NotAsDescribed: 1, WrongItem: 2, DamagedInTransit: 3, ChangedMind: 4, Defective: 5 };
const S = { Paid: 1, AdjustmentProposed: 2, Shipped: 3, Disputed: 4, Completed: 5, Refunded: 6, ReturnApproved: 7, ReturnShipped: 8 };

let passed = 0;
const failures = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const local = network.name === "hardhat";
  const [deployer] = await ethers.getSigners();
  let info, operator, treasurySigner = null;

  if (local) {
    info = await deployAll();
    operator = info._localSigners.s1;
    treasurySigner = info._localSigners.s2;
  } else {
    info = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "deployments", `${network.name}.json`), "utf8"));
    if (!info.mockDeployed) throw new Error("Needs MockUSDT (it mints test funds).");
    for (const [role, addr] of [["owner", info.owner], ["operator", info.operator]]) {
      if (addr.toLowerCase() !== deployer.address.toLowerCase())
        throw new Error(`The deployer key must also be the ${role} (${addr}) to run this test.`);
    }
    operator = deployer;
    if (process.env.TREASURY_PRIVATE_KEY) {
      treasurySigner = new ethers.Wallet(process.env.TREASURY_PRIVATE_KEY, ethers.provider);
      if (treasurySigner.address.toLowerCase() !== info.treasury.toLowerCase()) treasurySigner = null;
    }
    // treasury is the deployer wallet itself: no extra key needed
    if (!treasurySigner && info.treasury.toLowerCase() === deployer.address.toLowerCase()) treasurySigner = deployer;
  }
  const owner = deployer; // checked above on testnet; deployAll uses deployer as owner locally

  const provider = ethers.provider;
  if (!local) useFixedGasPrice(provider); // throwaway wallets must not use the node's (sometimes too low) fee tip
  const chainId = (await provider.getNetwork()).chainId;
  const escrowAddr = info.escrow;
  const escrow = await ethers.getContractAt("PlexusEscrowV2", escrowAddr);
  const token = await ethers.getContractAt("MockUSDT", info.token);
  const treasuryAddr = info.treasury;

  // ------------------------------------------------------------ helpers
  // After each write, pause on public networks so the load-balanced RPC has the new block everywhere
  const wait = async (p) => {
    const rc = await (await p).wait();
    if (!local) await sleep(2500);
    return rc;
  };
  async function eventually(read, expected, tries = 12) {
    let v;
    for (let i = 0; i < tries; i++) {
      v = await read();
      if (v === expected) return v;
      if (local) break;
      await sleep(1500);
    }
    return v;
  }
  async function check(label, read, expected) {
    const got = await eventually(read, expected);
    if (got === expected) { passed++; console.log(`  PASS ${label}`); }
    else { failures.push(label); console.log(`  FAIL ${label}: got ${got}, expected ${expected}`); }
  }
  // Over a real RPC a custom error arrives as a raw 4-byte selector ("execution reverted: 0x472e017e"),
  // so compare selectors as well as names. A wrong error is retried (no state changed) in case the
  // node was a block behind.
  async function reverts(label, fn, errName) {
    const want = escrow.interface.getError(errName)?.selector;
    let text = "";
    for (let attempt = 0; attempt < (local ? 1 : 3); attempt++) {
      try {
        await fn();
        failures.push(label); console.log(`  FAIL ${label}: did not revert`);
        return;
      } catch (e) {
        text = `${e.revert?.name || ""} ${e.shortMessage || ""} ${e.message || ""}`;
        const selectors = text.match(/0x[0-9a-fA-F]{8}/g) || [];
        if (text.includes(errName) || (want && selectors.includes(want))) {
          passed++; console.log(`  PASS ${label} (reverts ${errName})`);
          return;
        }
      }
      if (!local) await sleep(3000);
    }
    failures.push(label); console.log(`  FAIL ${label}: wrong error: ${text.slice(0, 120)}`);
  }
  const latest = async () => (await provider.getBlock("latest")).timestamp;
  // Shipping dates must be >= the payment and <= the block that includes the tx. On a load-balanced
  // RPC the chain tip can be AHEAD of the node that estimates gas, so use the order's own recorded
  // times (always safe) instead of the tip.
  async function orderTime(r, field) {
    for (let i = 0; i < 15; i++) {
      const v = (await escrow.getOrder(r))[field];
      if (v > 0n) return v;
      if (local) break;
      await sleep(2000);
    }
    throw new Error(`order ${field} not visible on the node`);
  }
  const bal = (a) => escrow.balances(a);
  const ref = (a) => escrow.refunds(a);
  const status = async (r) => Number((await escrow.getOrder(r)).status);

  // ------------------------------------------------------------ wallets
  const mk = () => ethers.Wallet.createRandom().connect(provider);
  const buyer = mk(), buyerR = mk(), seller = mk(), referrer = mk(), other = mk();
  console.log(`Network ${network.name} | escrow ${escrowAddr}\nbuyer ${buyer.address}\nseller ${seller.address}\n`);
  const gasFor = (w) => (local ? "1" : w === buyer || w === seller ? "0.015" : "0.004");
  for (const w of [buyer, buyerR, seller, referrer, other])
    await wait(deployer.sendTransaction({ to: w.address, value: ethers.parseEther(gasFor(w)) }));
  for (const w of [buyer, buyerR, seller, other]) {
    await wait(token.mint(w.address, E(5000)));
    await wait(token.connect(w).approve(escrowAddr, ethers.MaxUint256));
  }
  console.log("wallets funded\n");

  const domain = { name: "PlexusEscrow", version: "2", chainId, verifyingContract: escrowAddr };
  const types = {
    Quote: [
      { name: "orderRef", type: "bytes32" }, { name: "buyer", type: "address" }, { name: "seller", type: "address" },
      { name: "referrer", type: "address" }, { name: "productAmount", type: "uint256" },
      { name: "deliveryAmount", type: "uint256" }, { name: "feeBps", type: "uint16" },
      { name: "international", type: "bool" }, { name: "validUntil", type: "uint256" },
    ],
  };
  let counter = 0;
  async function quote(b, product, delivery, referrerAddr = ZERO) {
    return {
      orderRef: H(`ft-${Date.now()}-${counter++}`), buyer: b.address, seller: seller.address, referrer: referrerAddr,
      productAmount: E(product), deliveryAmount: E(delivery), feeBps: info.feeBps, international: false,
      validUntil: (await latest()) + 3600,
    };
  }
  async function pay(product, delivery, b = buyer, referrerAddr = ZERO) {
    const q = await quote(b, product, delivery, referrerAddr);
    await wait(escrow.connect(b).createOrder(q, await operator.signTypedData(domain, types, q)));
    return q.orderRef;
  }
  const ship = async (r) =>
    wait(escrow.connect(seller).markShipped(r, H("DHL"), H("TRACK"), H("proof"), await orderTime(r, "paidAt")));
  async function disputed(product, delivery) {
    const r = await pay(product, delivery);
    await ship(r);
    await wait(escrow.connect(buyer).openDispute(r, H("problem")));
    return r;
  }

  // ------------------------------------------------------------ 1. happy path
  console.log("1. Pay -> ship -> confirm -> withdraw");
  const t0 = await bal(treasuryAddr);
  let r = await pay(100, 10);
  await check("order is Paid", () => status(r), S.Paid);
  await reverts("unsigned buyer cannot pay for someone else", async () => {
    const q = await quote(buyer, 1, 0);
    await wait(escrow.connect(other).createOrder(q, await operator.signTypedData(domain, types, q)));
  }, "NotBuyer");
  await reverts("tampered quote rejected", async () => {
    const q = await quote(buyer, 1, 0);
    const sig = await operator.signTypedData(domain, types, q);
    await wait(escrow.connect(buyer).createOrder({ ...q, productAmount: E(2) }, sig));
  }, "BadSignature");
  await ship(r);
  await reverts("only buyer confirms", () => wait(escrow.connect(other).confirmReceipt(r)), "NotBuyer");
  await wait(escrow.connect(buyer).confirmReceipt(r));
  await check("seller credited 108", async () => (await bal(seller.address)).toString(), E(108).toString());
  await check("treasury credited 2", async () => ((await bal(treasuryAddr)) - t0).toString(), E(2).toString());
  await wait(escrow.connect(seller).withdraw());
  await check("seller wallet got 108", async () => (await token.balanceOf(seller.address)).toString(), (E(5000) + E(108)).toString());

  // ------------------------------------------------------------ 2. referral
  console.log("\n2. Referral rewards and cashback");
  const tr0 = await bal(treasuryAddr);
  r = await pay(1000, 0, buyerR, referrer.address);
  await ship(r);
  await wait(escrow.connect(buyerR).confirmReceipt(r));
  await check("referrer reward 6", async () => (await escrow.rewards(referrer.address)).toString(), E(6).toString());
  await check("buyer cashback 4", async () => (await escrow.rewards(buyerR.address)).toString(), E(4).toString());
  await check("treasury got 10 (fee 20 - 6 - 4)", async () => ((await bal(treasuryAddr)) - tr0).toString(), E(10).toString());
  await reverts("rewards need verification", () => wait(escrow.connect(referrer).withdrawRewards()), "NotVerified");
  await reverts("only operator verifies", () => wait(escrow.connect(other).setVerified(referrer.address, true)), "NotOperator");
  await wait(escrow.connect(operator).setVerified(referrer.address, true));
  await wait(escrow.connect(referrer).withdrawRewards());
  await check("referrer received 6 USDT", async () => (await token.balanceOf(referrer.address)).toString(), E(6).toString());
  await wait(escrow.connect(operator).setVerified(buyerR.address, true));
  await reverts("cashback 4 below $5 minimum", () => wait(escrow.connect(buyerR).withdrawRewards()), "BelowMinimum");
  await reverts("referrer cannot change later", async () => {
    const q = await quote(buyerR, 1, 0, other.address);
    await wait(escrow.connect(buyerR).createOrder(q, await operator.signTypedData(domain, types, q)));
  }, "ReferrerMismatch");

  // ------------------------------------------------------------ 3. cancel + refund
  console.log("\n3. Seller cancels, buyer withdraws refund");
  r = await pay(50, 5);
  await reverts("only seller cancels", () => wait(escrow.connect(other).cancelBySeller(r)), "NotSeller");
  await wait(escrow.connect(seller).cancelBySeller(r));
  await check("order Refunded", () => status(r), S.Refunded);
  const b0 = await token.balanceOf(buyer.address);
  await wait(escrow.connect(buyer).withdrawRefund());
  await check("buyer got 55 back", async () => ((await token.balanceOf(buyer.address)) - b0).toString(), E(55).toString());

  // ------------------------------------------------------------ 4. delivery adjustment
  console.log("\n4. Delivery fee adjustment");
  r = await pay(100, 10);
  const b1 = await token.balanceOf(buyer.address);
  await wait(escrow.connect(seller).proposeDeliveryAdjustment(r, E(4), H("cheaper")));
  await check("lower fee refunds 6 immediately", async () => ((await token.balanceOf(buyer.address)) - b1).toString(), E(6).toString());
  await reverts("adjustment only once", () => wait(escrow.connect(seller).proposeDeliveryAdjustment(r, E(9), H("x"))), "AdjustmentAlreadyUsed");
  await wait(escrow.connect(seller).cancelBySeller(r));
  r = await pay(100, 10);
  await wait(escrow.connect(seller).proposeDeliveryAdjustment(r, E(25), H("heavier")));
  await check("order AdjustmentProposed", () => status(r), S.AdjustmentProposed);
  await reverts("cannot ship during proposal", () => ship(r), "WrongStatus");
  await wait(escrow.connect(buyer).acceptDeliveryAdjustment(r));
  await check("accepted: back to Paid", () => status(r), S.Paid);
  await check("delivery now 25", async () => (await escrow.getOrder(r)).deliveryAmount.toString(), E(25).toString());
  await wait(escrow.connect(seller).cancelBySeller(r));
  r = await pay(100, 10);
  await wait(escrow.connect(seller).proposeDeliveryAdjustment(r, E(25), H("heavier")));
  await wait(escrow.connect(buyer).declineDeliveryAdjustment(r));
  await check("declined: order Refunded", () => status(r), S.Refunded);
  await wait(escrow.connect(buyer).withdrawRefund());

  // ------------------------------------------------------------ 5. disputes
  console.log("\n5. Disputes");
  r = await disputed(100, 10);
  await check("order Disputed", () => status(r), S.Disputed);
  await wait(escrow.connect(seller).concedeDispute(r));
  await check("seller conceded: Refunded", () => status(r), S.Refunded);
  r = await disputed(100, 10);
  await wait(escrow.connect(buyer).withdrawDispute(r));
  await check("buyer withdrew: Completed", () => status(r), S.Completed);
  r = await disputed(100, 10);
  await reverts("only owner resolves", () => wait(escrow.connect(other).resolveDispute(r, 0, 0)), "OwnableUnauthorizedAccount");
  await reverts("cannot refund more than paid", () => wait(escrow.connect(owner).resolveDispute(r, E(101), 0)), "InvalidAmount");
  await wait(escrow.connect(owner).extendDispute(r));
  await reverts("extend only once", () => wait(escrow.connect(owner).extendDispute(r)), "AlreadyExtended");
  const s0 = await bal(seller.address), f0 = await bal(treasuryAddr), rb0 = await ref(buyer.address);
  await wait(escrow.connect(owner).resolveDispute(r, E(40), 0));
  await check("owner split: seller +68.8", async () => ((await bal(seller.address)) - s0).toString(), E("68.8").toString());
  await check("owner split: treasury +1.2", async () => ((await bal(treasuryAddr)) - f0).toString(), E("1.2").toString());
  await check("owner split: buyer refund +40", async () => ((await ref(buyer.address)) - rb0).toString(), E(40).toString());
  await wait(escrow.connect(buyer).withdrawRefund());

  // ------------------------------------------------------------ 6. returns
  console.log("\n6. Returns");
  r = await disputed(100, 10);
  await reverts("only owner approves return", () => wait(escrow.connect(other).approveReturn(r, Reason.Defective, E(5))), "OwnableUnauthorizedAccount");
  await wait(escrow.connect(owner).approveReturn(r, Reason.Defective, E(5)));
  await check("order ReturnApproved", () => status(r), S.ReturnApproved);
  await reverts("buyer cannot ship before postage funded", () =>
    wait(escrow.connect(buyer).markReturnShipped(r, H("c"), H("t"), H("p"), 0)), "ReturnNotFunded");
  await wait(escrow.connect(seller).fundReturnPostage(r));
  await wait(escrow.connect(buyer).markReturnShipped(r, H("DHL"), H("RET"), H("p"), await orderTime(r, "shippedAt")));
  await check("order ReturnShipped", () => status(r), S.ReturnShipped);
  await check("postage reimbursed to buyer", async () => (await ref(buyer.address)).toString(), E(5).toString());
  await wait(escrow.connect(seller).confirmReturnReceived(r));
  await check("return done: Refunded", () => status(r), S.Refunded);
  await check("buyer refunds = 110 + 5 postage", async () => (await ref(buyer.address)).toString(), E(115).toString());
  await wait(escrow.connect(buyer).withdrawRefund());

  r = await disputed(100, 10);
  await wait(escrow.connect(owner).approveReturn(r, Reason.ChangedMind, 0));
  await wait(escrow.connect(buyer).markReturnShipped(r, H("DHL"), H("RET2"), H("p"), await orderTime(r, "shippedAt")));
  await wait(escrow.connect(seller).contestReturn(r, H("box was empty")));
  await check("contested: back to Disputed", () => status(r), S.Disputed);
  await reverts("buyer cannot withdraw after return decision", () => wait(escrow.connect(buyer).withdrawDispute(r)), "ReturnAlreadyDecided");
  await wait(escrow.connect(owner).resolveDispute(r, 0, 0));
  await check("owner sided with seller: Completed", () => status(r), S.Completed);

  r = await disputed(100, 10);
  await wait(escrow.connect(owner).approveReturn(r, Reason.ChangedMind, 0));
  await wait(escrow.connect(buyer).markReturnShipped(r, H("DHL"), H("RET3"), H("p"), await orderTime(r, "shippedAt")));
  const s1 = await bal(seller.address);
  await wait(escrow.connect(seller).confirmReturnReceived(r));
  await check("changed mind: product refunded 100", async () => (await ref(buyer.address)).toString(), E(100).toString());
  await check("changed mind: seller keeps delivery 10", async () => ((await bal(seller.address)) - s1).toString(), E(10).toString());
  await wait(escrow.connect(buyer).withdrawRefund());

  r = await disputed(100, 10);
  const s2 = await bal(seller.address);
  await wait(escrow.connect(owner).resolveWrongAddress(r, E(5)));
  await check("wrong address: buyer refund 95", async () => (await ref(buyer.address)).toString(), E(95).toString());
  await check("wrong address: seller +15", async () => ((await bal(seller.address)) - s2).toString(), E(15).toString());
  await wait(escrow.connect(buyer).withdrawRefund());

  // ------------------------------------------------------------ 7. admin
  console.log("\n7. Admin: pause, fee timelock, rescue");
  await wait(escrow.connect(owner).pause());
  await reverts("paused: new orders blocked", () => pay(1, 0), "EnforcedPause");
  await wait(escrow.connect(owner).unpause());
  await check("unpaused: orders work again", async () => { const x = await pay(1, 0); await wait(escrow.connect(seller).cancelBySeller(x)); await wait(escrow.connect(buyer).withdrawRefund()); return true; }, true);
  await reverts("fee above 10% rejected", () => wait(escrow.connect(owner).proposeFeeConfig(1001, 0, 0)), "InvalidFeeConfig");
  await wait(escrow.connect(owner).proposeFeeConfig(500, 1000, 1000));
  await check("fee change pending", async () => (await escrow.pendingFeeEta()) > 0n, true);
  await reverts("fee change blocked by 48h timelock", () => wait(escrow.connect(other).executeFeeConfig()), "TooEarly");
  await wait(escrow.connect(owner).cancelFeeConfig());
  await check("fee change cancelled", async () => (await escrow.pendingFeeEta()).toString(), "0");
  await check("fee still 2%", async () => Number((await escrow.feeConfig()).feeBps), 200);

  const tr1 = await token.balanceOf(treasuryAddr);
  await wait(token.connect(other).transfer(escrowAddr, E(7)));
  await reverts("only owner rescues", () => wait(escrow.connect(other).rescueExcess()), "OwnableUnauthorizedAccount");
  await wait(escrow.connect(owner).rescueExcess());
  await check("rescued 7 to treasury", async () => ((await token.balanceOf(treasuryAddr)) - tr1).toString(), E(7).toString());

  if (treasurySigner) {
    const before = await token.balanceOf(treasuryAddr);
    const owed = await bal(treasuryAddr);
    await wait(escrow.connect(treasurySigner).withdraw());
    await check("treasury withdrew its fees", async () => ((await token.balanceOf(treasuryAddr)) - before).toString(), owed.toString());
  } else console.log("  (skipped treasury withdraw: no TREASURY_PRIVATE_KEY)");

  // ------------------------------------------------------------ 8. solvency
  console.log("\n8. Solvency");
  await wait(escrow.connect(seller).withdraw());
  await check("escrow token balance == totalHeld", async () => (await token.balanceOf(escrowAddr)).toString(), (await escrow.totalHeld()).toString());

  console.log(`\n${passed} passed, ${failures.length} failed`);
  if (failures.length) { console.log("FAILED:\n - " + failures.join("\n - ")); process.exitCode = 1; }
  if (!local) console.log(`BscScan: https://testnet.bscscan.com/address/${escrowAddr}`);
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
