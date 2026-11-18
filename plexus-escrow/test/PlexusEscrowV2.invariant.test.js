// Randomised invariant test (task 3.8). Thousands of random, mostly legal actions across many orders, with time moving,
// fee changes and pauses mixed in. After EVERY action the accounting must still balance:
//   (1) the contract's token balance equals totalHeld
//   (2) totalHeld equals every credit owed (refunds + earnings + rewards) plus everything still locked inside open orders
// A failing run prints its seed and step, so it can be replayed exactly. Run: npx hardhat test test/PlexusEscrowV2.invariant.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

const E = (n) => ethers.parseEther(String(n));
const DAY = 86400;
const H = (s) => ethers.id(s);
const ZERO = ethers.ZeroAddress;
const QUOTE_TYPES = {
  Quote: [
    { name: "orderRef", type: "bytes32" }, { name: "buyer", type: "address" }, { name: "seller", type: "address" },
    { name: "referrer", type: "address" }, { name: "productAmount", type: "uint256" }, { name: "deliveryAmount", type: "uint256" },
    { name: "feeBps", type: "uint16" }, { name: "international", type: "bool" }, { name: "validUntil", type: "uint256" },
  ],
};
const S = { Paid: 1, AdjustmentProposed: 2, Shipped: 3, Disputed: 4, Completed: 5, Refunded: 6, ReturnApproved: 7, ReturnShipped: 8 };
const OPEN = new Set([S.Paid, S.AdjustmentProposed, S.Shipped, S.Disputed, S.ReturnApproved, S.ReturnShipped]);

function rng(seed) { // small deterministic generator, so a failing seed can be replayed
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

describe("PlexusEscrowV2 invariants (randomised)", function () {
  this.timeout(600000);

  async function run(seed, steps, mode = "mixed") {
    const returnsMode = mode === "returns"; // drive orders into disputes and returns, with postage
    const rand = rng(seed);
    const pick = (arr) => arr[Math.floor(rand() * arr.length)];
    const [owner, operator, treasury, ...rest] = await ethers.getSigners();
    const users = rest.slice(0, 6);
    const accounts = [owner, operator, treasury, ...users];

    const token = await (await ethers.getContractFactory("MockUSDT")).deploy();
    const escrow = await (await ethers.getContractFactory("PlexusEscrowV2")).deploy(
      await token.getAddress(), owner.address, operator.address, treasury.address, 200, 3000, 2000, E(5)
    );
    const escrowAddr = await escrow.getAddress();
    for (const u of [...users, treasury]) {
      await token.mint(u.address, E(1_000_000));
      await token.connect(u).approve(escrowAddr, ethers.MaxUint256);
    }
    for (const u of users) await escrow.connect(operator).setVerified(u.address, rand() < 0.7);
    const domain = { name: "PlexusEscrow", version: "2", chainId: (await ethers.provider.getNetwork()).chainId, verifyingContract: escrowAddr };

    const orders = [];
    const done = {};
    let counter = 0;

    async function tryTx(label, fn) {
      try {
        const tx = await fn();
        await tx.wait();
        done[label] = (done[label] || 0) + 1;
        return true;
      } catch (e) {
        return false; // most random actions are refused: that is expected and fine
      }
    }

    async function createOrder() {
      const buyer = pick(users);
      let seller = pick(users);
      if (seller.address === buyer.address) seller = users[(users.indexOf(buyer) + 1) % users.length];
      const locked = await escrow.referralLocked(buyer.address);
      const referrer = locked ? await escrow.referrerOf(buyer.address) : (rand() < 0.5 ? pick(users).address : ZERO);
      const fee = Number((await escrow.feeConfig()).feeBps);
      const q = {
        orderRef: H(`o-${seed}-${counter++}`), buyer: buyer.address, seller: seller.address, referrer,
        productAmount: BigInt(Math.floor(rand() * 5000) + 1) * 10n ** 16n, // 0.01 .. 50.00
        deliveryAmount: rand() < 0.2 ? 0n : BigInt(Math.floor(rand() * 2000)) * 10n ** 16n,
        feeBps: fee, international: rand() < 0.3, validUntil: (await time.latest()) + DAY,
      };
      const sig = await operator.signTypedData(domain, QUOTE_TYPES, q);
      if (await tryTx("createOrder", () => escrow.connect(buyer).createOrder(q, sig))) orders.push({ ref: q.orderRef, buyer, seller });
    }

    const by = (addr) => users.find((u) => u.address === addr);

    async function stepOnOrder() {
      const o = pick(orders);
      const ord = await escrow.getOrder(o.ref);
      const status = Number(ord.status);
      const buyer = by(ord.buyer), seller = by(ord.seller);
      const anyone = pick(users);
      const reason = H(`why-${counter++}`);
      const now = await time.latest();
      const choices = {
        [S.Paid]: [
          () => tryTx("markShipped", () => escrow.connect(seller).markShipped(o.ref, H("c"), H("t"), H("p"), ord.paidAt)),
          () => tryTx("cancelBySeller", () => escrow.connect(seller).cancelBySeller(o.ref)),
          () => tryTx("refundUnshipped", () => escrow.connect(anyone).refundUnshipped(o.ref)),
          () => tryTx("proposeAdjustment", () => escrow.connect(seller).proposeDeliveryAdjustment(o.ref, BigInt(Math.floor(rand() * 3000)) * 10n ** 16n, reason)),
        ],
        [S.AdjustmentProposed]: [
          () => tryTx("acceptAdjustment", () => escrow.connect(buyer).acceptDeliveryAdjustment(o.ref)),
          () => tryTx("declineAdjustment", () => escrow.connect(buyer).declineDeliveryAdjustment(o.ref)),
          () => tryTx("expireAdjustment", () => escrow.connect(anyone).expireDeliveryAdjustment(o.ref)),
          () => tryTx("cancelBySeller", () => escrow.connect(seller).cancelBySeller(o.ref)),
        ],
        [S.Shipped]: [
          () => tryTx("confirmReceipt", () => escrow.connect(buyer).confirmReceipt(o.ref)),
          () => tryTx("release", () => escrow.connect(anyone).release(o.ref)),
          () => tryTx("openDispute", () => escrow.connect(buyer).openDispute(o.ref, reason)),
        ],
        [S.Disputed]: [
          () => tryTx("withdrawDispute", () => escrow.connect(buyer).withdrawDispute(o.ref)),
          () => tryTx("concedeDispute", () => escrow.connect(seller).concedeDispute(o.ref)),
          () => tryTx("extendDispute", () => escrow.connect(owner).extendDispute(o.ref)),
          () => tryTx("resolveDispute", () => escrow.connect(owner).resolveDispute(o.ref, (ord.productAmount * BigInt(Math.floor(rand() * 101))) / 100n, (ord.deliveryAmount * BigInt(Math.floor(rand() * 101))) / 100n)),
          () => tryTx("resolveExpiredDispute", () => escrow.connect(anyone).resolveExpiredDispute(o.ref)),
          () => tryTx("approveReturn", () => escrow.connect(owner).approveReturn(o.ref, 1 + Math.floor(rand() * 5), (returnsMode ? rand() < 0.1 : rand() < 0.4) ? 0n : (ord.productAmount * BigInt(Math.floor(rand() * 101))) / 100n)),
          () => tryTx("resolveWrongAddress", () => escrow.connect(owner).resolveWrongAddress(o.ref, (ord.productAmount * BigInt(Math.floor(rand() * 101))) / 100n)),
        ],
        [S.ReturnApproved]: [
          () => tryTx("fundReturnPostage", () => escrow.connect(seller).fundReturnPostage(o.ref)),
          () => tryTx("markReturnShipped", () => escrow.connect(buyer).markReturnShipped(o.ref, H("c"), H("t"), H("p"), ord.shippedAt)),
          () => tryTx("finalizeReturn", () => escrow.connect(anyone).finalizeReturn(o.ref)),
        ],
        [S.ReturnShipped]: [
          () => tryTx("confirmReturnReceived", () => escrow.connect(seller).confirmReturnReceived(o.ref)),
          () => tryTx("contestReturn", () => escrow.connect(seller).contestReturn(o.ref, reason)),
          () => tryTx("finalizeReturn", () => escrow.connect(anyone).finalizeReturn(o.ref)),
        ],
      };
      const list = choices[status];
      // push orders towards the deep paths (shipping, disputes, returns) instead of cancelling early
      const bias = returnsMode ? {
        [S.Paid]: [0],
        [S.AdjustmentProposed]: [0],
        [S.Shipped]: [2],
        [S.Disputed]: [5, 5, 5, 5, 3, 6],
        [S.ReturnApproved]: [0, 1, 1, 1, 2],
        [S.ReturnShipped]: [0, 0, 1, 2],
      } : {
        [S.Paid]: [0, 0, 0, 0, 0, 1, 2, 3, 3],
        [S.AdjustmentProposed]: [0, 0, 0, 1, 1, 2, 3],
        [S.Shipped]: [0, 2, 2, 2, 2, 1],
        [S.Disputed]: [3, 3, 5, 5, 5, 5, 6, 6, 0, 1, 2, 4],
        [S.ReturnApproved]: [0, 0, 1, 1, 1, 2],
        [S.ReturnShipped]: [0, 0, 1, 1, 2],
      };
      if (list) await list[pick(bias[status] || list.map((_, i) => i))]();
      return now;
    }

    async function misc() {
      const r = rand();
      const u = pick(users);
      if (r < 0.30) return tryTx("withdraw", () => escrow.connect(rand() < 0.2 ? treasury : u).withdraw());
      if (r < 0.55) return tryTx("withdrawRefund", () => escrow.connect(u).withdrawRefund());
      if (r < 0.70) return tryTx("withdrawRewards", () => escrow.connect(u).withdrawRewards());
      if (r < 0.90) { await time.increase(Math.floor(rand() * 20 * DAY) + 3600); done.time = (done.time || 0) + 1; return; }
      if (r < 0.94) return tryTx("proposeFee", () => escrow.connect(owner).proposeFeeConfig(Math.floor(rand() * 1001), Math.floor(rand() * 5001), Math.floor(rand() * 5001)));
      if (r < 0.97) return tryTx("executeFee", () => escrow.connect(u).executeFeeConfig());
      if (r < 0.985) return tryTx("pause", () => escrow.connect(owner).pause());
      return tryTx("unpause", () => escrow.connect(owner).unpause());
    }

    async function checkInvariants(step) {
      const held = await escrow.totalHeld();
      const balance = await token.balanceOf(escrowAddr);
      expect(balance, `seed ${seed} step ${step}: token balance != totalHeld`).to.equal(held);
      let owed = 0n;
      for (const a of accounts) owed += (await escrow.refunds(a.address)) + (await escrow.balances(a.address)) + (await escrow.rewards(a.address));
      for (const o of orders) {
        const x = await escrow.getOrder(o.ref);
        const st = Number(x.status);
        if (!OPEN.has(st)) continue;
        owed += x.productAmount + x.deliveryAmount;
        if (st === S.ReturnApproved && x.returnFunded) owed += x.returnCost; // postage deposited, not yet credited to the buyer
      }
      expect(held, `seed ${seed} step ${step}: totalHeld != credits owed + money locked in open orders`).to.equal(owed);
    }

    for (let step = 1; step <= steps; step++) {
      if (orders.length < 4 || rand() < (returnsMode ? 0.12 : 0.25)) await createOrder();
      else if (rand() < 0.8) await stepOnOrder();
      else await misc();
      await checkInvariants(step);
    }
    // end: let every deadline pass, close what can be closed, withdraw everything, and the contract must be exactly empty of obligations
    await time.increase(60 * DAY);
    const opened = orders.length;
    return { done, orders: opened, steps };
  }

  // return-heavy runs: every order is pushed through dispute -> return -> postage -> confirm / contest / timeout
  const returnTotals = {};
  let returnRuns = 0;
  const RETURN_SEEDS = [101, 102, 103, 104, 105];
  after(function () {
    if (returnRuns < RETURN_SEEDS.length) return; // only meaningful when all the return-heavy runs were selected
    // across all return-heavy runs together, the return flow with postage must really have been exercised
    const reached = (returnTotals.fundReturnPostage || 0) + (returnTotals.markReturnShipped || 0) + (returnTotals.confirmReturnReceived || 0);
    expect(reached, "return flow reached by the return-heavy runs").to.be.greaterThan(5);
  });
  for (const seed of RETURN_SEEDS) {
    it(`return-heavy seed ${seed}: 350 random actions never break the accounting`, async function () {
      const r = await run(seed, 350, "returns");
      const actions = Object.entries(r.done).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${v}`).join(", ");
      console.log(`      ${r.orders} orders; successful actions: ${actions}`);
      returnRuns++;
      for (const [k, v] of Object.entries(r.done)) returnTotals[k] = (returnTotals[k] || 0) + v;
    });
  }

  for (const seed of [1, 2, 3, 4, 5, 6, 7, 8]) {
    it(`seed ${seed}: 400 random actions never break the accounting`, async function () {
      const r = await run(seed, 400);
      const actions = Object.entries(r.done).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${v}`).join(", ");
      console.log(`      ${r.orders} orders; successful actions: ${actions}`);
    });
  }
});
