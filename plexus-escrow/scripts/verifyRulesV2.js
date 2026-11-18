// POST-DEPLOYMENT CHECK. Verifies the PLEXUS business rules (documents/PLEXUS-Order-Workflow.pdf,
// flowcharts 1-7) against a DEPLOYED PlexusEscrowV2, through real RPC calls, using time travel
// for every deadline. The same rules are unit-tested in test/PlexusEscrowV2.test.js (run that first).
//   npx hardhat node                                              (terminal 1)
//   npx hardhat run scripts/deployV2.js --network localhost       (terminal 2)
//   npx hardhat run scripts/verifyRulesV2.js --network localhost
// Needs a chain where time can be moved (hardhat / localhost). It cannot run on a public testnet:
// there the owner/operator/treasury must be local signers and deadlines cannot be skipped.
// Without --network it deploys a fresh copy in-process and checks that.
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");
const { deployAll } = require("./lib/deployV2");

const A = (x) => (typeof x === "bigint" ? x : ethers.parseEther(String(x)));
const E = A;
const H = (s) => ethers.id(s);
const ZERO = ethers.ZeroAddress;
const DAY = 86400;
const HOUR = 3600;
const Reason = { NotAsDescribed: 1, WrongItem: 2, DamagedInTransit: 3, ChangedMind: 4, Defective: 5 };
const S = { Paid: 1, AdjustmentProposed: 2, Shipped: 3, Disputed: 4, Completed: 5, Refunded: 6, ReturnApproved: 7, ReturnShipped: 8 };

const results = [];
function eq(actual, expected, what) {
  if (String(actual) !== String(expected)) throw new Error(`${what}: got ${actual}, expected ${expected}`);
}

async function main() {
  const provider = ethers.provider;
  const signers = await ethers.getSigners();
  const deployer = signers[0];
  let info;
  if (network.name === "hardhat") info = await deployAll();
  else info = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "deployments", `${network.name}.json`), "utf8"));
  const find = (a) => signers.find((s) => s.address.toLowerCase() === a.toLowerCase());
  const owner = find(info.owner), operator = find(info.operator), treasurySigner = find(info.treasury);
  if (!owner || !operator || !treasurySigner) throw new Error("owner/operator/treasury must be local signers");
  const treasury = info.treasury;

  const escrow = await ethers.getContractAt("PlexusEscrowV2", info.escrow);
  const token = await ethers.getContractAt("MockUSDT", info.token);
  const chainId = (await provider.getNetwork()).chainId;
  const domain = { name: "PlexusEscrow", version: "2", chainId, verifyingContract: info.escrow };
  const types = { Quote: [
    { name: "orderRef", type: "bytes32" }, { name: "buyer", type: "address" }, { name: "seller", type: "address" },
    { name: "referrer", type: "address" }, { name: "productAmount", type: "uint256" },
    { name: "deliveryAmount", type: "uint256" }, { name: "feeBps", type: "uint16" },
    { name: "international", type: "bool" }, { name: "validUntil", type: "uint256" } ] };

  // ---- helpers
  const w = async (p) => (await p).wait();
  const latest = async () => (await provider.getBlock("latest")).timestamp;
  const tsOf = async (rc) => (await provider.getBlock(rc.blockNumber)).timestamp;
  const advance = async (s) => { await provider.send("evm_increaseTime", [s]); await provider.send("evm_mine", []); };
  const bal = (a) => escrow.balances(a);
  const refunds = (a) => escrow.refunds(a);
  const rewards = (a) => escrow.rewards(a);
  const order = (r) => escrow.getOrder(r);
  const status = async (r) => Number((await order(r)).status);
  let n = 0;

  async function user() {
    const u = ethers.Wallet.createRandom().connect(provider);
    await w(deployer.sendTransaction({ to: u.address, value: ethers.parseEther("10") }));
    await w(token.mint(u.address, E(100000)));
    await w(token.connect(u).approve(info.escrow, ethers.MaxUint256));
    return u;
  }
  const actors = async () => ({ buyer: await user(), seller: await user() });

  async function pay(buyer, seller, product, delivery, o = {}) {
    const q = {
      orderRef: H(`rule-${Date.now()}-${n++}`), buyer: buyer.address, seller: seller.address,
      referrer: o.referrer || ZERO, productAmount: A(product), deliveryAmount: A(delivery),
      feeBps: o.feeBps ?? Number((await escrow.feeConfig()).feeBps), international: !!o.international,
      validUntil: o.validUntil ?? (await latest()) + HOUR,
    };
    const sig = await (o.signer || operator).signTypedData(domain, types, q);
    await w(escrow.connect(buyer).createOrder(q, sig));
    return q.orderRef;
  }
  async function ship(r, seller, o = {}) {
    return w(escrow.connect(seller).markShipped(r, o.carrier ?? H("DHL"), o.tracking ?? H("TRK"), H("proof"), o.shippedAt ?? (await latest())));
  }
  async function shipped(buyer, seller, product, delivery, o = {}) {
    const r = await pay(buyer, seller, product, delivery, o);
    await ship(r, seller);
    return r;
  }
  async function disputed(buyer, seller, product, delivery, o = {}) {
    const r = await shipped(buyer, seller, product, delivery, o);
    await w(escrow.connect(buyer).openDispute(r, H("problem")));
    return r;
  }
  async function rejects(fn, errName) {
    try { await fn(); } catch (e) {
      const text = `${e.revert?.name || ""} ${e.shortMessage || ""} ${e.message || ""}`;
      if (text.includes(errName)) return;
      throw new Error(`expected ${errName}, got: ${text.slice(0, 140)}`);
    }
    throw new Error(`expected ${errName}, but the call succeeded`);
  }
  const rule = (id, flow, title, fn) => results.push({ id, flow, title, fn });

  // =============================================================== 1. ORDER FLOW / QUOTE
  rule("Q1", "1", "Quote with an outdated fee is refused, nothing is taken", async () => {
    const { buyer, seller } = await actors();
    const before = await token.balanceOf(buyer.address);
    await rejects(async () => pay(buyer, seller, 100, 15, { feeBps: 300 }), "FeeMismatch");
    eq(await token.balanceOf(buyer.address), before, "buyer balance");
  });
  rule("Q2", "1", "Expired quote is refused", async () => {
    const { buyer, seller } = await actors();
    await rejects(async () => pay(buyer, seller, 100, 15, { validUntil: (await latest()) - 1 }), "QuoteExpired");
  });
  rule("Q3", "1", "Only a quote signed by the PLEXUS server key is accepted", async () => {
    const { buyer, seller } = await actors();
    await rejects(async () => pay(buyer, seller, 100, 15, { signer: buyer }), "BadSignature");
  });
  rule("Q4", "1", "Payment locks product + delivery in escrow, status Paid", async () => {
    const { buyer, seller } = await actors();
    const before = await token.balanceOf(info.escrow);
    const r = await pay(buyer, seller, 100, 15);
    eq((await token.balanceOf(info.escrow)) - before, E(115), "escrow received");
    eq(await status(r), S.Paid, "status");
  });

  // =============================================================== 2. SHIPPING
  rule("S1", "2", "Shipping needs carrier and tracking number", async () => {
    const { buyer, seller } = await actors();
    const r = await pay(buyer, seller, 100, 15);
    await rejects(async () => ship(r, seller, { carrier: ethers.ZeroHash }), "InvalidShipment");
    await rejects(async () => ship(r, seller, { tracking: ethers.ZeroHash }), "InvalidShipment");
  });
  rule("S2", "2", "Shipping date cannot be before payment or in the future", async () => {
    const { buyer, seller } = await actors();
    const r = await pay(buyer, seller, 100, 15);
    const paidAt = Number((await order(r)).paidAt);
    await rejects(async () => ship(r, seller, { shippedAt: paidAt - 1 }), "InvalidShipment");
    await rejects(async () => ship(r, seller, { shippedAt: (await latest()) + 1000 }), "InvalidShipment");
  });
  rule("S3", "2", "Not shipped within 7 days: anyone triggers a full refund, no commission", async () => {
    const { buyer, seller } = await actors();
    const other = await user();
    const t0 = await bal(treasury);
    const r = await pay(buyer, seller, 100, 15);
    await advance(6 * DAY);
    await rejects(async () => w(escrow.connect(other).refundUnshipped(r)), "TooEarly");
    await advance(DAY);
    await rejects(async () => ship(r, seller), "TooLate");
    await w(escrow.connect(other).refundUnshipped(r));
    eq(await refunds(buyer.address), E(115), "buyer refund");
    eq((await bal(treasury)) - t0, 0, "commission");
    eq(await status(r), S.Refunded, "status");
  });
  rule("S4", "2", "Release timer is 14 days (30 international), starts at shipping, backdating cannot shorten it", async () => {
    const { buyer, seller } = await actors();
    for (const [intl, days] of [[false, 14], [true, 30]]) {
      const r = await pay(buyer, seller, 100, 15, { international: intl });
      const paidAt = Number((await order(r)).paidAt);
      await advance(3 * DAY);
      const rc = await ship(r, seller, { shippedAt: paidAt }); // backdated to payment day
      eq(Number((await order(r)).releaseAt), (await tsOf(rc)) + days * DAY, `releaseAt (${intl ? "intl" : "domestic"})`);
    }
  });
  rule("S5", "2", "After the release timer anyone releases: seller paid product - 2% + delivery", async () => {
    const { buyer, seller } = await actors();
    const other = await user();
    const r = await shipped(buyer, seller, 100, 15);
    await advance(14 * DAY - 60);
    await rejects(async () => w(escrow.connect(other).release(r)), "TooEarly");
    await advance(120);
    await w(escrow.connect(other).release(r));
    eq(await bal(seller.address), E(113), "seller");
  });

  // =============================================================== 3. DELIVERY FEE CHANGE
  rule("A1", "3", "Lower delivery fee: difference goes to the buyer's wallet at once, order stays Paid, only one change", async () => {
    const { buyer, seller } = await actors();
    const r = await pay(buyer, seller, 100, 15);
    const before = await token.balanceOf(buyer.address);
    await w(escrow.connect(seller).proposeDeliveryAdjustment(r, E(5), H("cheaper")));
    eq((await token.balanceOf(buyer.address)) - before, E(10), "buyer wallet");
    eq(await status(r), S.Paid, "status");
    await rejects(async () => w(escrow.connect(seller).proposeDeliveryAdjustment(r, E(4), H("again"))), "AdjustmentAlreadyUsed");
  });
  rule("A2", "3", "Only the seller can propose, only while Paid and before the 7-day deadline", async () => {
    const { buyer, seller } = await actors();
    const r = await pay(buyer, seller, 100, 15);
    await rejects(async () => w(escrow.connect(buyer).proposeDeliveryAdjustment(r, E(20), H("x"))), "NotSeller");
    await ship(r, seller);
    await rejects(async () => w(escrow.connect(seller).proposeDeliveryAdjustment(r, E(20), H("x"))), "WrongStatus");
    const r2 = await pay(buyer, seller, 100, 15);
    await advance(7 * DAY);
    await rejects(async () => w(escrow.connect(seller).proposeDeliveryAdjustment(r2, E(20), H("x"))), "TooLate");
  });
  rule("A3", "3", "Higher fee: shipping blocked; buyer pays only the difference; fresh 7-day window", async () => {
    const { buyer, seller } = await actors();
    const r = await pay(buyer, seller, 100, 15);
    await w(escrow.connect(seller).proposeDeliveryAdjustment(r, E(25), H("heavier")));
    eq(await status(r), S.AdjustmentProposed, "status");
    await rejects(async () => ship(r, seller), "WrongStatus");
    await advance(3 * DAY);
    const before = await token.balanceOf(buyer.address);
    const rc = await w(escrow.connect(buyer).acceptDeliveryAdjustment(r));
    eq(before - (await token.balanceOf(buyer.address)), E(10), "buyer paid");
    eq(await status(r), S.Paid, "status");
    eq(Number((await order(r)).shipDeadline), (await tsOf(rc)) + 7 * DAY, "fresh shipping deadline");
  });
  rule("A4", "3", "Buyer declines or stays silent 5 days: full refund (anyone can trigger the timeout)", async () => {
    const { buyer, seller } = await actors();
    const other = await user();
    const r = await pay(buyer, seller, 100, 15);
    await w(escrow.connect(seller).proposeDeliveryAdjustment(r, E(25), H("x")));
    await w(escrow.connect(buyer).declineDeliveryAdjustment(r));
    eq(await refunds(buyer.address), E(115), "decline refund");
    const buyer2 = await user();
    const r2 = await pay(buyer2, seller, 100, 15);
    await w(escrow.connect(seller).proposeDeliveryAdjustment(r2, E(25), H("x")));
    await advance(5 * DAY - 60);
    await rejects(async () => w(escrow.connect(other).expireDeliveryAdjustment(r2)), "TooEarly");
    await advance(120);
    await rejects(async () => w(escrow.connect(buyer2).acceptDeliveryAdjustment(r2)), "TooLate");
    await w(escrow.connect(other).expireDeliveryAdjustment(r2));
    eq(await refunds(buyer2.address), E(115), "timeout refund");
  });

  // =============================================================== 4. DISPUTE
  rule("D1", "4", "Dispute only on a Shipped order, by the buyer, before release; it stops auto-release", async () => {
    const { buyer, seller } = await actors();
    const other = await user();
    const r0 = await pay(buyer, seller, 100, 15);
    await rejects(async () => w(escrow.connect(buyer).openDispute(r0, H("x"))), "WrongStatus");
    const r = await shipped(buyer, seller, 100, 15);
    await rejects(async () => w(escrow.connect(other).openDispute(r, H("x"))), "NotBuyer");
    await w(escrow.connect(buyer).openDispute(r, H("x")));
    await advance(15 * DAY);
    await rejects(async () => w(escrow.connect(other).release(r)), "WrongStatus");
    const r2 = await shipped(buyer, seller, 100, 15);
    await advance(14 * DAY + 5);
    await rejects(async () => w(escrow.connect(buyer).openDispute(r2, H("x"))), "TooLate");
  });
  rule("D2", "4", "Buyer withdraws the dispute: seller paid as normal (minus 2% of product)", async () => {
    const { buyer, seller } = await actors();
    const t0 = await bal(treasury);
    const r = await disputed(buyer, seller, 100, 15);
    await w(escrow.connect(buyer).withdrawDispute(r));
    eq(await bal(seller.address), E(113), "seller");
    eq((await bal(treasury)) - t0, E(2), "commission");
  });
  rule("D3", "4", "Seller concedes: full refund to buyer, no commission", async () => {
    const { buyer, seller } = await actors();
    const t0 = await bal(treasury);
    const r = await disputed(buyer, seller, 100, 15);
    await w(escrow.connect(seller).concedeDispute(r));
    eq(await refunds(buyer.address), E(115), "buyer");
    eq(await bal(seller.address), 0, "seller");
    eq((await bal(treasury)) - t0, 0, "commission");
  });
  rule("D4", "4", "Team decides: buyer wins / seller wins / split; commission only on product kept, never on delivery", async () => {
    const a = await actors(), b = await actors(), c = await actors(), d = await actors();
    const t0 = await bal(treasury);
    let r = await disputed(a.buyer, a.seller, 100, 15);
    await rejects(async () => w(escrow.connect(a.buyer).resolveDispute(r, 0, 0)), "OwnableUnauthorizedAccount");
    await w(escrow.connect(owner).resolveDispute(r, E(100), E(15)));
    eq(await refunds(a.buyer.address), E(115), "buyer-wins refund");
    eq((await bal(treasury)) - t0, 0, "buyer-wins commission");
    r = await disputed(b.buyer, b.seller, 100, 15);
    await w(escrow.connect(owner).resolveDispute(r, 0, 0));
    eq(await bal(b.seller.address), E(113), "seller-wins");
    r = await disputed(c.buyer, c.seller, 100, 15);
    const t1 = await bal(treasury);
    await w(escrow.connect(owner).resolveDispute(r, E(40), E(5)));
    eq(await refunds(c.buyer.address), E(45), "split buyer");
    eq(await bal(c.seller.address), E("68.8"), "split seller (60 + 10 - 1.2)");
    eq((await bal(treasury)) - t1, E("1.2"), "split commission");
    r = await disputed(d.buyer, d.seller, 100, 15);
    const t2 = await bal(treasury);
    await w(escrow.connect(owner).resolveDispute(r, E(100), 0));
    eq(await bal(d.seller.address), E(15), "delivery kept, no commission on it");
    eq((await bal(treasury)) - t2, 0, "no commission on delivery");
  });
  rule("D5", "4", "Team may extend once by 14 days (28 total); not after the deadline", async () => {
    const { buyer, seller } = await actors();
    const other = await user();
    const r = await disputed(buyer, seller, 100, 15);
    const d0 = Number((await order(r)).disputeDeadline);
    await rejects(async () => w(escrow.connect(other).extendDispute(r)), "OwnableUnauthorizedAccount");
    await w(escrow.connect(owner).extendDispute(r));
    eq(Number((await order(r)).disputeDeadline), d0 + 14 * DAY, "extended deadline");
    await rejects(async () => w(escrow.connect(owner).extendDispute(r)), "AlreadyExtended");
    await advance(14 * DAY + 60); // past the original deadline: team can still decide
    await rejects(async () => w(escrow.connect(other).resolveExpiredDispute(r)), "TooEarly");
    await w(escrow.connect(owner).resolveDispute(r, 0, 0));
    const r2 = await disputed(buyer, seller, 100, 15);
    await advance(14 * DAY + 60);
    await rejects(async () => w(escrow.connect(owner).extendDispute(r2)), "TooLate");
  });
  rule("D6", "4", "Team silent 14 days: buyer refunded in full automatically (anyone triggers); team can no longer decide", async () => {
    const { buyer, seller } = await actors();
    const other = await user();
    const r = await disputed(buyer, seller, 100, 15);
    await advance(14 * DAY - 60);
    await rejects(async () => w(escrow.connect(other).resolveExpiredDispute(r)), "TooEarly");
    await advance(120);
    await rejects(async () => w(escrow.connect(owner).resolveDispute(r, 0, 0)), "TooLate");
    await w(escrow.connect(other).resolveExpiredDispute(r));
    eq(await refunds(buyer.address), E(115), "buyer");
  });

  // =============================================================== 5. RETURNS
  rule("T1", "5", "Wrong address ($12 return cost): buyer $88, seller $27, no commission", async () => {
    const { buyer, seller } = await actors();
    const t0 = await bal(treasury);
    const r = await disputed(buyer, seller, 100, 15);
    await w(escrow.connect(owner).resolveWrongAddress(r, E(12)));
    eq(await refunds(buyer.address), E(88), "buyer");
    eq(await bal(seller.address), E(27), "seller");
    eq((await bal(treasury)) - t0, 0, "commission");
  });
  rule("T2", "5", "Changed mind: buyer pays the carrier; buyer gets $100, seller keeps $15, no commission", async () => {
    const { buyer, seller } = await actors();
    const t0 = await bal(treasury);
    const r = await disputed(buyer, seller, 100, 15);
    await rejects(async () => w(escrow.connect(owner).approveReturn(r, Reason.ChangedMind, E(8))), "InvalidAmount");
    await w(escrow.connect(owner).approveReturn(r, Reason.ChangedMind, 0));
    await w(escrow.connect(buyer).markReturnShipped(r, H("DHL"), H("RET"), H("p"), await latest()));
    await w(escrow.connect(seller).confirmReturnReceived(r));
    eq(await refunds(buyer.address), E(100), "buyer");
    eq(await bal(seller.address), E(15), "seller");
    eq((await bal(treasury)) - t0, 0, "commission");
  });
  rule("T3", "5", "Seller-fault return ($8 postage): seller deposits (wallet), buyer gets $115 + $8, seller $0 and pays the $8", async () => {
    const { buyer, seller } = await actors();
    const r = await disputed(buyer, seller, 100, 15);
    await w(escrow.connect(owner).approveReturn(r, Reason.Defective, E(8)));
    const wallet0 = await token.balanceOf(seller.address);
    await w(escrow.connect(seller).fundReturnPostage(r));
    eq(wallet0 - (await token.balanceOf(seller.address)), E(8), "seller wallet paid");
    await w(escrow.connect(buyer).markReturnShipped(r, H("DHL"), H("RET"), H("p"), await latest()));
    eq(await refunds(buyer.address), E(8), "postage credited to buyer on shipping");
    await w(escrow.connect(seller).confirmReturnReceived(r));
    eq(await refunds(buyer.address), E(123), "buyer total");
    eq(await bal(seller.address), 0, "seller earnings");
  });
  rule("T3b", "5", "Postage deposit comes from the seller's earnings first, then the wallet", async () => {
    const { buyer, seller } = await actors();
    const earn = await shipped(buyer, seller, 100, 15);
    await w(escrow.connect(buyer).confirmReceipt(earn)); // seller earns 113
    const r = await disputed(buyer, seller, 100, 15);
    await w(escrow.connect(owner).approveReturn(r, Reason.WrongItem, E(8)));
    const wallet0 = await token.balanceOf(seller.address);
    await w(escrow.connect(seller).fundReturnPostage(r));
    eq(await token.balanceOf(seller.address), wallet0, "wallet untouched");
    eq(await bal(seller.address), E(105), "earnings reduced by 8");
  });
  rule("T4", "5", "Seller does not deposit postage within 3 days: full refund, buyer keeps the item", async () => {
    const { buyer, seller } = await actors();
    const other = await user();
    const r = await disputed(buyer, seller, 100, 15);
    await w(escrow.connect(owner).approveReturn(r, Reason.Defective, E(8)));
    await advance(3 * DAY - 60);
    await rejects(async () => w(escrow.connect(other).finalizeReturn(r)), "TooEarly");
    await advance(120);
    await rejects(async () => w(escrow.connect(seller).fundReturnPostage(r)), "TooLate");
    await w(escrow.connect(other).finalizeReturn(r));
    eq(await refunds(buyer.address), E(115), "buyer");
    eq(await status(r), S.Refunded, "status");
  });
  rule("T5", "5", "Buyer does not ship back within 7 days: seller paid as normal, postage deposit returned", async () => {
    const { buyer, seller } = await actors();
    const other = await user();
    const t0 = await bal(treasury);
    const r = await disputed(buyer, seller, 100, 15);
    await w(escrow.connect(owner).approveReturn(r, Reason.Defective, E(8)));
    await w(escrow.connect(seller).fundReturnPostage(r));
    await advance(7 * DAY + 60);
    await rejects(async () => w(escrow.connect(buyer).markReturnShipped(r, H("DHL"), H("RET"), H("p"), await latest())), "TooLate");
    await w(escrow.connect(other).finalizeReturn(r));
    eq(await bal(seller.address), E(113) + E(8), "seller (sale + deposit back)");
    eq((await bal(treasury)) - t0, E(2), "commission");
  });
  rule("T6", "5", "Seller silent after the return ships (14 days, 30 international): buyer refunded by reason", async () => {
    const { buyer, seller } = await actors();
    const other = await user();
    for (const [intl, days] of [[false, 14], [true, 30]]) {
      const b = await user();
      const r = await disputed(b, seller, 100, 15, { international: intl });
      await w(escrow.connect(owner).approveReturn(r, Reason.Defective, E(8)));
      await w(escrow.connect(seller).fundReturnPostage(r));
      await w(escrow.connect(b).markReturnShipped(r, H("DHL"), H("RET"), H("p"), await latest()));
      await advance(days * DAY - 120);
      await rejects(async () => w(escrow.connect(other).finalizeReturn(r)), "TooEarly");
      await advance(240);
      await w(escrow.connect(other).finalizeReturn(r));
      eq(await refunds(b.address), E(123), `buyer refund (${intl ? "intl" : "domestic"})`);
    }
  });
  rule("T7", "5", "Seller contests within the window -> back to the team; if the team is silent the normal outcome applies", async () => {
    const { buyer, seller } = await actors();
    const other = await user();
    // changed mind, contested, team silent: buyer $100, seller keeps $15
    let r = await disputed(buyer, seller, 100, 15);
    await w(escrow.connect(owner).approveReturn(r, Reason.ChangedMind, 0));
    await w(escrow.connect(buyer).markReturnShipped(r, H("DHL"), H("RET"), H("p"), await latest()));
    await w(escrow.connect(seller).contestReturn(r, H("empty box")));
    eq(await status(r), S.Disputed, "back to dispute");
    await advance(14 * DAY + 60);
    await w(escrow.connect(other).resolveExpiredDispute(r));
    eq(await refunds(buyer.address), E(100), "changed-mind buyer");
    eq(await bal(seller.address), E(15), "changed-mind seller");
    // seller at fault, contested, team silent: buyer $115 + postage
    const b2 = await user();
    r = await disputed(b2, seller, 100, 15);
    await w(escrow.connect(owner).approveReturn(r, Reason.Defective, E(8)));
    await w(escrow.connect(seller).fundReturnPostage(r));
    await w(escrow.connect(b2).markReturnShipped(r, H("DHL"), H("RET"), H("p"), await latest()));
    await w(escrow.connect(seller).contestReturn(r, H("not what I sent")));
    await advance(14 * DAY + 60);
    await w(escrow.connect(other).resolveExpiredDispute(r));
    eq(await refunds(b2.address), E(123), "seller-fault buyer");
  });

  // =============================================================== 6. SETTLEMENT / COMMISSION
  rule("P1", "6", "Spec example: $100 + $15 with a referrer -> seller $113, referrer $0.60, buyer $0.40, PLEXUS $1.00", async () => {
    const { buyer, seller } = await actors();
    const referrer = await user();
    const t0 = await bal(treasury);
    const r = await shipped(buyer, seller, 100, 15, { referrer: referrer.address });
    await w(escrow.connect(buyer).confirmReceipt(r));
    eq(await bal(seller.address), E(113), "seller");
    eq(await rewards(referrer.address), E("0.6"), "referrer");
    eq(await rewards(buyer.address), E("0.4"), "buyer cashback");
    eq((await bal(treasury)) - t0, E(1), "PLEXUS");
  });
  rule("P2", "6", "No referrer: PLEXUS keeps the full 2% commission", async () => {
    const { buyer, seller } = await actors();
    const t0 = await bal(treasury);
    const r = await shipped(buyer, seller, 100, 15);
    await w(escrow.connect(buyer).confirmReceipt(r));
    eq((await bal(treasury)) - t0, E(2), "PLEXUS");
    eq(await rewards(buyer.address), 0, "buyer cashback");
  });
  rule("P3", "6", "Referrer is the seller: referrer 0%, buyer 20%, PLEXUS 80%", async () => {
    const { buyer, seller } = await actors();
    const t0 = await bal(treasury);
    const r = await shipped(buyer, seller, 100, 15, { referrer: seller.address });
    await w(escrow.connect(buyer).confirmReceipt(r));
    eq(await rewards(seller.address), 0, "seller as referrer");
    eq(await rewards(buyer.address), E("0.4"), "buyer cashback");
    eq((await bal(treasury)) - t0, E("1.6"), "PLEXUS");
    eq(await bal(seller.address), E(113), "seller");
  });
  rule("P4", "6", "Rounding: every wei is accounted for, dust stays with PLEXUS", async () => {
    const { buyer, seller } = await actors();
    const referrer = await user();
    const t0 = await bal(treasury);
    const product = 1000000000000000007n, delivery = 3n;
    const r = await shipped(buyer, seller, product, delivery, { referrer: referrer.address });
    await w(escrow.connect(buyer).confirmReceipt(r));
    const sum = (await bal(seller.address)) + (await rewards(referrer.address)) + (await rewards(buyer.address)) + ((await bal(treasury)) - t0);
    eq(sum, product + delivery, "sum of all credits");
  });

  // =============================================================== 7. WITHDRAWALS
  rule("W1", "7", "Buyer refunds: no minimum, full amount, even while paused", async () => {
    const { buyer, seller } = await actors();
    const r = await pay(buyer, seller, 1n, 0);
    await w(escrow.connect(seller).cancelBySeller(r));
    await w(escrow.connect(owner).pause());
    try {
      const before = await token.balanceOf(buyer.address);
      await w(escrow.connect(buyer).withdrawRefund());
      eq((await token.balanceOf(buyer.address)) - before, 1n, "1 wei refund");
    } finally { await w(escrow.connect(owner).unpause()); }
  });
  rule("W2", "7", "Seller earnings need $5 minimum; treasury is exempt", async () => {
    const { buyer, seller } = await actors();
    const r = await shipped(buyer, seller, 3, 0);
    await w(escrow.connect(buyer).confirmReceipt(r)); // seller 2.94, treasury +0.06
    await rejects(async () => w(escrow.connect(seller).withdraw()), "BelowMinimum");
    await w(escrow.connect(treasurySigner).withdraw()); // drain
    const buyer2 = await user();
    const r2 = await shipped(buyer2, seller, 2, 0);
    await w(escrow.connect(buyer2).confirmReceipt(r2)); // treasury +0.04 (< $5)
    const before = await token.balanceOf(treasury);
    await w(escrow.connect(treasurySigner).withdraw());
    eq((await token.balanceOf(treasury)) - before, E("0.04"), "treasury withdrew < $5");
  });
  rule("W3", "7", "Rewards need a passed identity check and $5", async () => {
    const { buyer, seller } = await actors();
    const referrer = await user();
    const r = await shipped(buyer, seller, 1000, 0, { referrer: referrer.address });
    await w(escrow.connect(buyer).confirmReceipt(r)); // referrer 6, buyer 4
    await rejects(async () => w(escrow.connect(referrer).withdrawRewards()), "NotVerified");
    await rejects(async () => w(escrow.connect(buyer).setVerified(referrer.address, true)), "NotOperator");
    await w(escrow.connect(operator).setVerified(referrer.address, true));
    const before = await token.balanceOf(referrer.address);
    await w(escrow.connect(referrer).withdrawRewards());
    eq((await token.balanceOf(referrer.address)) - before, E(6), "referrer paid");
    await w(escrow.connect(operator).setVerified(buyer.address, true));
    await rejects(async () => w(escrow.connect(buyer).withdrawRewards()), "BelowMinimum");
  });
  rule("W4", "7", "Pause stops only new orders; shipping, confirming and disputes keep working", async () => {
    const { buyer, seller } = await actors();
    const r1 = await pay(buyer, seller, 100, 15);
    const r2 = await shipped(buyer, seller, 100, 15);
    await w(escrow.connect(owner).pause());
    try {
      await rejects(async () => pay(buyer, seller, 100, 15), "EnforcedPause");
      await ship(r1, seller);
      await w(escrow.connect(buyer).openDispute(r1, H("x")));
      await w(escrow.connect(buyer).confirmReceipt(r2));
      eq(await bal(seller.address), E(113), "seller paid while paused");
    } finally { await w(escrow.connect(owner).unpause()); }
  });

  // =============================================================== ADMIN
  rule("F1", "6", "Fee change: 48h timelock, new orders only, old orders keep their fee, max 10%", async () => {
    const { buyer, seller } = await actors();
    const t0 = await bal(treasury);
    const old = await shipped(buyer, seller, 100, 15);
    await rejects(async () => w(escrow.connect(owner).proposeFeeConfig(1001, 3000, 2000)), "InvalidFeeConfig");
    await w(escrow.connect(owner).proposeFeeConfig(500, 3000, 2000));
    await advance(47 * HOUR);
    await rejects(async () => w(escrow.connect(buyer).executeFeeConfig()), "TooEarly");
    await advance(2 * HOUR);
    await w(escrow.connect(buyer).executeFeeConfig()); // anyone
    try {
      await rejects(async () => pay(buyer, seller, 100, 15, { feeBps: 200 }), "FeeMismatch");
      await w(escrow.connect(buyer).confirmReceipt(old));
      eq((await bal(treasury)) - t0, E(2), "old order still 2%");
      const fresh = await shipped(buyer, seller, 100, 15, { feeBps: 500 });
      const t1 = await bal(treasury);
      await w(escrow.connect(buyer).confirmReceipt(fresh));
      eq((await bal(treasury)) - t1, E(5), "new order 5%");
    } finally {
      await w(escrow.connect(owner).proposeFeeConfig(200, 3000, 2000));
      await advance(49 * HOUR);
      await w(escrow.connect(owner).executeFeeConfig());
    }
    eq(Number((await escrow.feeConfig()).feeBps), 200, "fee restored");
  });
  rule("F2", "1", "Referrer is locked on the buyer's first order; self-referral refused", async () => {
    const { buyer, seller } = await actors();
    const ref1 = await user(), ref2 = await user();
    await rejects(async () => pay(buyer, seller, 10, 0, { referrer: buyer.address }), "InvalidReferrer");
    await pay(buyer, seller, 10, 0, { referrer: ref1.address });
    await rejects(async () => pay(buyer, seller, 10, 0, { referrer: ref2.address }), "ReferrerMismatch");
    await rejects(async () => pay(buyer, seller, 10, 0), "ReferrerMismatch");
    eq(await escrow.referrerOf(buyer.address), ref1.address, "locked referrer");
  });
  rule("F3", "-", "Ownership is two-step; renouncing is disabled; operator can be rotated", async () => {
    const next = await user();
    await rejects(async () => w(escrow.connect(owner).renounceOwnership()), "RenounceDisabled");
    await w(escrow.connect(owner).transferOwnership(next.address));
    eq(await escrow.owner(), owner.address, "owner unchanged until accepted");
    await w(escrow.connect(next).acceptOwnership());
    eq(await escrow.owner(), next.address, "new owner");
    await w(escrow.connect(next).transferOwnership(owner.address));
    await w(escrow.connect(owner).acceptOwnership());
    eq(await escrow.owner(), owner.address, "owner restored");
    const { buyer, seller } = await actors();
    const newOp = await user();
    await w(escrow.connect(owner).setOperator(newOp.address));
    try {
      await rejects(async () => pay(buyer, seller, 10, 0), "BadSignature"); // old key no longer valid
      await pay(buyer, seller, 10, 0, { signer: newOp });
    } finally { await w(escrow.connect(owner).setOperator(operator.address)); }
  });
  rule("G1", "-", "Solvency: contract token balance equals everything it owes (totalHeld)", async () => {
    eq(await token.balanceOf(info.escrow), await escrow.totalHeld(), "balance vs totalHeld");
  });

  // =============================================================== RUN
  console.log(`Verifying PlexusEscrowV2 ${info.escrow} on ${network.name} (chain ${chainId})\n`);
  let pass = 0;
  for (const r of results) {
    process.stdout.write(`${r.id.padEnd(4)} [flow ${r.flow}] ${r.title}\n     `);
    try { await r.fn(); r.ok = true; pass++; console.log("PASS"); }
    catch (e) { r.ok = false; r.err = e.message; console.log(`FAIL  ${e.message}`); }
  }
  console.log(`\n${pass}/${results.length} business rules verified`);
  const bad = results.filter((r) => !r.ok);
  if (bad.length) { console.log("FAILED: " + bad.map((r) => r.id).join(", ")); process.exitCode = 1; }
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
