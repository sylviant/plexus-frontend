const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

const E = (n) => ethers.parseEther(String(n));
const DAY = 24 * 60 * 60;
const HOUR = 60 * 60;
const ref = (s) => ethers.id(s); // bytes32 order ref
const H = (s) => ethers.id(s); // generic bytes32 hash
const ZERO = ethers.ZeroAddress;

const Status = {
  None: 0, Paid: 1, AdjustmentProposed: 2, Shipped: 3, Disputed: 4,
  Completed: 5, Refunded: 6, ReturnApproved: 7, ReturnShipped: 8,
};
const Reason = {
  None: 0, NotAsDescribed: 1, WrongItem: 2, DamagedInTransit: 3,
  ChangedMind: 4, Defective: 5, WrongAddress: 6,
};

const FEE = 200; // 2%
const REF_BPS = 3000; // 30% of commission
const CASHBACK_BPS = 2000; // 20% of commission
const MIN_WD = E(5);

const QUOTE_TYPES = {
  Quote: [
    { name: "orderRef", type: "bytes32" },
    { name: "buyer", type: "address" },
    { name: "seller", type: "address" },
    { name: "referrer", type: "address" },
    { name: "productAmount", type: "uint256" },
    { name: "deliveryAmount", type: "uint256" },
    { name: "feeBps", type: "uint16" },
    { name: "international", type: "bool" },
    { name: "validUntil", type: "uint256" },
  ],
};

describe("PlexusEscrowV2", function () {
  async function deploy() {
    const [owner, operator, treasury, buyer, seller, referrer, other] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockUSDT");
    const token = await Token.deploy();
    const Escrow = await ethers.getContractFactory("PlexusEscrowV2");
    const escrow = await Escrow.deploy(
      await token.getAddress(), owner.address, operator.address, treasury.address,
      FEE, REF_BPS, CASHBACK_BPS, MIN_WD
    );
    const escrowAddr = await escrow.getAddress();

    for (const u of [buyer, seller, referrer, other]) {
      await token.mint(u.address, E(10_000));
      await token.connect(u).approve(escrowAddr, ethers.MaxUint256);
    }

    const domain = {
      name: "PlexusEscrow", version: "2",
      chainId: (await ethers.provider.getNetwork()).chainId,
      verifyingContract: escrowAddr,
    };

    async function makeQuote(over = {}) {
      return {
        orderRef: ref("order-1"),
        buyer: buyer.address,
        seller: seller.address,
        referrer: ZERO,
        productAmount: E(100),
        deliveryAmount: E(10),
        feeBps: FEE,
        international: false,
        validUntil: (await time.latest()) + DAY,
        ...over,
      };
    }
    const sign = (q, signer = operator) => signer.signTypedData(domain, QUOTE_TYPES, q);

    async function pay(over = {}, who = buyer) {
      const q = await makeQuote(over);
      await escrow.connect(who).createOrder(q, await sign(q));
      return q;
    }
    async function ship(orderRef, who = seller) {
      return escrow.connect(who).markShipped(orderRef, H("DHL"), H("TRACK1"), H("proof"), await time.latest());
    }
    async function payAndShip(over = {}) {
      const q = await pay(over);
      await ship(q.orderRef);
      return q;
    }
    async function payShipDispute(over = {}) {
      const q = await payAndShip(over);
      await escrow.connect(buyer).openDispute(q.orderRef, H("reason"));
      return q;
    }

    return { escrow, token, escrowAddr, owner, operator, treasury, buyer, seller, referrer, other,
      domain, makeQuote, sign, pay, ship, payAndShip, payShipDispute };
  }

  // Solvency invariant: contract token balance == totalHeld == sum of every credit bucket.
  async function expectSolvent(f, accounts) {
    const { escrow, token, escrowAddr } = f;
    const bal = await token.balanceOf(escrowAddr);
    expect(await escrow.totalHeld()).to.equal(bal);
    let owed = 0n;
    for (const a of accounts) {
      owed += (await escrow.refunds(a)) + (await escrow.balances(a)) + (await escrow.rewards(a));
    }
    return { bal, owed };
  }

  // ----------------------------------------------------------------- deployment
  describe("deployment", function () {
    it("sets config", async function () {
      const f = await loadFixture(deploy);
      expect(await f.escrow.token()).to.equal(await f.token.getAddress());
      expect(await f.escrow.owner()).to.equal(f.owner.address);
      expect(await f.escrow.operator()).to.equal(f.operator.address);
      expect(await f.escrow.treasury()).to.equal(f.treasury.address);
      expect(await f.escrow.minWithdrawal()).to.equal(MIN_WD);
      const c = await f.escrow.feeConfig();
      expect([c.feeBps, c.referrerBps, c.cashbackBps].map(Number)).to.deep.equal([FEE, REF_BPS, CASHBACK_BPS]);
    });

    it("rejects zero addresses and bad fee configs", async function () {
      const f = await loadFixture(deploy);
      const Escrow = await ethers.getContractFactory("PlexusEscrowV2");
      const t = await f.token.getAddress();
      await expect(Escrow.deploy(ZERO, f.owner.address, f.operator.address, f.treasury.address, FEE, 0, 0, 0))
        .to.be.revertedWithCustomError(f.escrow, "ZeroAddress");
      await expect(Escrow.deploy(t, f.owner.address, ZERO, f.treasury.address, FEE, 0, 0, 0))
        .to.be.revertedWithCustomError(f.escrow, "ZeroAddress");
      await expect(Escrow.deploy(t, f.owner.address, f.operator.address, ZERO, FEE, 0, 0, 0))
        .to.be.revertedWithCustomError(f.escrow, "ZeroAddress");
      await expect(Escrow.deploy(t, f.owner.address, f.operator.address, f.treasury.address, 1001, 0, 0, 0))
        .to.be.revertedWithCustomError(f.escrow, "InvalidFeeConfig");
      await expect(Escrow.deploy(t, f.owner.address, f.operator.address, f.treasury.address, FEE, 6000, 4001, 0))
        .to.be.revertedWithCustomError(f.escrow, "InvalidFeeConfig");
    });
  });

  // ----------------------------------------------------------------- createOrder
  describe("createOrder", function () {
    it("pulls funds, stores order, emits event", async function () {
      const f = await loadFixture(deploy);
      const q = await f.makeQuote();
      await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q)))
        .to.emit(f.escrow, "OrderCreated")
        .withArgs(q.orderRef, f.buyer.address, f.seller.address, q.productAmount, q.deliveryAmount, ZERO, FEE);
      const o = await f.escrow.getOrder(q.orderRef);
      expect(o.status).to.equal(Status.Paid);
      expect(o.buyer).to.equal(f.buyer.address);
      expect(await f.token.balanceOf(f.escrowAddr)).to.equal(E(110));
      expect(await f.escrow.totalHeld()).to.equal(E(110));
      expect(o.shipDeadline).to.equal(o.paidAt + BigInt(7 * DAY));
    });

    it("quoteDigest matches off-chain EIP-712 hash", async function () {
      const f = await loadFixture(deploy);
      const q = await f.makeQuote();
      expect(await f.escrow.quoteDigest(q)).to.equal(ethers.TypedDataEncoder.hash(f.domain, QUOTE_TYPES, q));
    });

    it("rejects non-buyer caller", async function () {
      const f = await loadFixture(deploy);
      const q = await f.makeQuote();
      await expect(f.escrow.connect(f.other).createOrder(q, await f.sign(q)))
        .to.be.revertedWithCustomError(f.escrow, "NotBuyer");
    });

    it("rejects expired quote", async function () {
      const f = await loadFixture(deploy);
      const q = await f.makeQuote({ validUntil: (await time.latest()) + 10 });
      const sig = await f.sign(q);
      await time.increase(20);
      await expect(f.escrow.connect(f.buyer).createOrder(q, sig))
        .to.be.revertedWithCustomError(f.escrow, "QuoteExpired");
    });

    it("rejects signature from non-operator and tampered quotes", async function () {
      const f = await loadFixture(deploy);
      const q = await f.makeQuote();
      await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q, f.other)))
        .to.be.revertedWithCustomError(f.escrow, "BadSignature");
      const sig = await f.sign(q);
      await expect(f.escrow.connect(f.buyer).createOrder({ ...q, productAmount: E(1) }, sig))
        .to.be.revertedWithCustomError(f.escrow, "BadSignature");
    });

    it("rejects duplicate order ref (replay)", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q)))
        .to.be.revertedWithCustomError(f.escrow, "OrderExists");
    });

    it("rejects bad seller, zero amount, fee mismatch", async function () {
      const f = await loadFixture(deploy);
      let q = await f.makeQuote({ seller: f.buyer.address });
      await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q)))
        .to.be.revertedWithCustomError(f.escrow, "InvalidSeller");
      q = await f.makeQuote({ seller: ZERO });
      await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q)))
        .to.be.revertedWithCustomError(f.escrow, "InvalidSeller");
      q = await f.makeQuote({ productAmount: 0 });
      await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q)))
        .to.be.revertedWithCustomError(f.escrow, "InvalidAmount");
      q = await f.makeQuote({ feeBps: 300 });
      await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q)))
        .to.be.revertedWithCustomError(f.escrow, "FeeMismatch");
    });

    it("reverts without allowance / when paused", async function () {
      const f = await loadFixture(deploy);
      await f.token.connect(f.buyer).approve(f.escrowAddr, 0);
      const q = await f.makeQuote();
      await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q))).to.be.reverted;
      await f.token.connect(f.buyer).approve(f.escrowAddr, ethers.MaxUint256);
      await f.escrow.pause();
      await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q)))
        .to.be.revertedWithCustomError(f.escrow, "EnforcedPause");
      await f.escrow.unpause();
      await f.escrow.connect(f.buyer).createOrder(q, await f.sign(q));
    });

    it("allows zero delivery amount", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay({ deliveryAmount: 0 });
      expect(await f.escrow.totalHeld()).to.equal(E(100));
      expect((await f.escrow.getOrder(q.orderRef)).deliveryAmount).to.equal(0);
    });

    describe("referrals", function () {
      it("locks referrer on first order and rejects a different one later", async function () {
        const f = await loadFixture(deploy);
        const q1 = await f.pay({ referrer: f.referrer.address });
        expect(await f.escrow.referrerOf(f.buyer.address)).to.equal(f.referrer.address);
        expect(await f.escrow.referralLocked(f.buyer.address)).to.equal(true);

        const q2 = await f.makeQuote({ orderRef: ref("o2"), referrer: f.other.address });
        await expect(f.escrow.connect(f.buyer).createOrder(q2, await f.sign(q2)))
          .to.be.revertedWithCustomError(f.escrow, "ReferrerMismatch");
        const q3 = await f.makeQuote({ orderRef: ref("o3"), referrer: ZERO });
        await expect(f.escrow.connect(f.buyer).createOrder(q3, await f.sign(q3)))
          .to.be.revertedWithCustomError(f.escrow, "ReferrerMismatch");
        const q4 = await f.makeQuote({ orderRef: ref("o4"), referrer: f.referrer.address });
        await f.escrow.connect(f.buyer).createOrder(q4, await f.sign(q4));
        expect((await f.escrow.getOrder(q1.orderRef)).referrer).to.equal(f.referrer.address);
      });

      it("locks 'no referrer' permanently", async function () {
        const f = await loadFixture(deploy);
        await f.pay();
        const q = await f.makeQuote({ orderRef: ref("o2"), referrer: f.referrer.address });
        await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q)))
          .to.be.revertedWithCustomError(f.escrow, "ReferrerMismatch");
      });

      it("rejects self-referral", async function () {
        const f = await loadFixture(deploy);
        const q = await f.makeQuote({ referrer: f.buyer.address });
        await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q)))
          .to.be.revertedWithCustomError(f.escrow, "InvalidReferrer");
      });

      it("excludes referrer when they are the seller (cashback only)", async function () {
        const f = await loadFixture(deploy);
        const q = await f.makeQuote({ referrer: f.seller.address });
        await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q)))
          .to.emit(f.escrow, "SellerReferrerExcluded").withArgs(q.orderRef, f.seller.address);
        const o = await f.escrow.getOrder(q.orderRef);
        expect(o.referrer).to.equal(ZERO);
        expect(o.referrerBps).to.equal(0);
        expect(o.cashbackBps).to.equal(CASHBACK_BPS);
      });
    });
  });

  // ----------------------------------------------------------------- happy path & settlement
  describe("shipping & settlement", function () {
    it("buyer confirms receipt: seller paid minus commission, treasury gets fee", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payAndShip();
      await expect(f.escrow.connect(f.buyer).confirmReceipt(q.orderRef))
        .to.emit(f.escrow, "Settled").withArgs(q.orderRef, E(108), E(2), 0);
      expect((await f.escrow.getOrder(q.orderRef)).status).to.equal(Status.Completed);
      expect(await f.escrow.balances(f.seller.address)).to.equal(E(108));
      expect(await f.escrow.balances(f.treasury.address)).to.equal(E(2));

      await f.escrow.connect(f.seller).withdraw();
      expect(await f.token.balanceOf(f.seller.address)).to.equal(E(10_000) + E(108));
      await f.escrow.connect(f.treasury).withdraw();
      expect(await f.token.balanceOf(f.treasury.address)).to.equal(E(2));
      expect(await f.escrow.totalHeld()).to.equal(0);
      expect(await f.token.balanceOf(f.escrowAddr)).to.equal(0);
    });

    it("splits commission with referrer and buyer cashback", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payAndShip({ referrer: f.referrer.address });
      await f.escrow.connect(f.buyer).confirmReceipt(q.orderRef);
      // commission 2.0 : referrer 30% = 0.6, cashback 20% = 0.4, treasury 1.0
      expect(await f.escrow.rewards(f.referrer.address)).to.equal(E("0.6"));
      expect(await f.escrow.rewards(f.buyer.address)).to.equal(E("0.4"));
      expect(await f.escrow.balances(f.treasury.address)).to.equal(E("1"));
      expect(await f.escrow.balances(f.seller.address)).to.equal(E(108));
      const { bal, owed } = await expectSolvent(f, [f.buyer.address, f.seller.address, f.referrer.address, f.treasury.address]);
      expect(owed).to.equal(bal);
    });

    it("markShipped validations", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      const now = await time.latest();
      await expect(f.escrow.connect(f.other).markShipped(q.orderRef, H("c"), H("t"), H("p"), now))
        .to.be.revertedWithCustomError(f.escrow, "NotSeller");
      await expect(f.escrow.connect(f.seller).markShipped(q.orderRef, ethers.ZeroHash, H("t"), H("p"), now))
        .to.be.revertedWithCustomError(f.escrow, "InvalidShipment");
      await expect(f.escrow.connect(f.seller).markShipped(q.orderRef, H("c"), ethers.ZeroHash, H("p"), now))
        .to.be.revertedWithCustomError(f.escrow, "InvalidShipment");
      await expect(f.escrow.connect(f.seller).markShipped(q.orderRef, H("c"), H("t"), H("p"), now + 1000))
        .to.be.revertedWithCustomError(f.escrow, "InvalidShipment"); // future
      await expect(f.escrow.connect(f.seller).markShipped(q.orderRef, H("c"), H("t"), H("p"), now - 1000))
        .to.be.revertedWithCustomError(f.escrow, "InvalidShipment"); // before payment
      await f.ship(q.orderRef);
      await expect(f.ship(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "WrongStatus");
    });

    it("cannot ship after the ship deadline", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      await time.increase(7 * DAY + 1);
      await expect(f.ship(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooLate");
    });

    it("release: domestic 14d, international 30d", async function () {
      const f = await loadFixture(deploy);
      const d = await f.payAndShip({ orderRef: ref("dom") });
      const i = await f.payAndShip({ orderRef: ref("intl"), international: true });
      await expect(f.escrow.release(d.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increase(14 * DAY + 5);
      await f.escrow.connect(f.other).release(d.orderRef); // anyone can call
      expect((await f.escrow.getOrder(d.orderRef)).status).to.equal(Status.Completed);
      await expect(f.escrow.release(i.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increase(16 * DAY);
      await f.escrow.release(i.orderRef);
      expect((await f.escrow.getOrder(i.orderRef)).status).to.equal(Status.Completed);
    });

    it("only buyer can confirmReceipt, only when Shipped", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      await expect(f.escrow.connect(f.buyer).confirmReceipt(q.orderRef))
        .to.be.revertedWithCustomError(f.escrow, "WrongStatus");
      await f.ship(q.orderRef);
      await expect(f.escrow.connect(f.other).confirmReceipt(q.orderRef))
        .to.be.revertedWithCustomError(f.escrow, "NotBuyer");
    });

    it("unknown order reverts", async function () {
      const f = await loadFixture(deploy);
      await expect(f.escrow.connect(f.buyer).confirmReceipt(ref("nope")))
        .to.be.revertedWithCustomError(f.escrow, "OrderNotFound");
    });
  });

  // ----------------------------------------------------------------- withdrawals
  describe("withdrawals", function () {
    it("seller below minimum cannot withdraw; treasury is exempt", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payAndShip({ productAmount: E(2), deliveryAmount: 0 });
      await f.escrow.connect(f.buyer).confirmReceipt(q.orderRef);
      // seller 1.96, treasury 0.04
      await expect(f.escrow.connect(f.seller).withdraw()).to.be.revertedWithCustomError(f.escrow, "BelowMinimum");
      await f.escrow.connect(f.treasury).withdraw();
      await expect(f.escrow.connect(f.treasury).withdraw()).to.be.revertedWithCustomError(f.escrow, "NothingToWithdraw");
    });

    it("rewards need verification and minimum", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payAndShip({ referrer: f.referrer.address, productAmount: E(1000), deliveryAmount: 0 });
      await f.escrow.connect(f.buyer).confirmReceipt(q.orderRef);
      // commission 20; referrer 6, cashback 4
      await expect(f.escrow.connect(f.referrer).withdrawRewards()).to.be.revertedWithCustomError(f.escrow, "NotVerified");
      await expect(f.escrow.connect(f.other).setVerified(f.referrer.address, true))
        .to.be.revertedWithCustomError(f.escrow, "NotOperator");
      await expect(f.escrow.connect(f.operator).setVerified(f.referrer.address, true))
        .to.emit(f.escrow, "VerifiedSet").withArgs(f.referrer.address, true);
      await f.escrow.connect(f.referrer).withdrawRewards();
      expect(await f.token.balanceOf(f.referrer.address)).to.equal(E(10_000) + E(6));
      // buyer cashback 4 < 5 minimum
      await f.escrow.connect(f.operator).setVerified(f.buyer.address, true);
      await expect(f.escrow.connect(f.buyer).withdrawRewards()).to.be.revertedWithCustomError(f.escrow, "BelowMinimum");
      await expect(f.escrow.connect(f.other).withdrawRewards()).to.be.revertedWithCustomError(f.escrow, "NotVerified");
    });

    it("refunds have no minimum", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay({ productAmount: 1, deliveryAmount: 0 });
      await f.escrow.connect(f.seller).cancelBySeller(q.orderRef);
      await f.escrow.connect(f.buyer).withdrawRefund();
      expect(await f.token.balanceOf(f.buyer.address)).to.equal(E(10_000));
      await expect(f.escrow.connect(f.buyer).withdrawRefund()).to.be.revertedWithCustomError(f.escrow, "NothingToWithdraw");
    });
  });

  // ----------------------------------------------------------------- pre-shipping exits
  describe("before shipping", function () {
    it("seller cancels: full refund", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      await expect(f.escrow.connect(f.other).cancelBySeller(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "NotSeller");
      await expect(f.escrow.connect(f.seller).cancelBySeller(q.orderRef))
        .to.emit(f.escrow, "OrderRefunded").withArgs(q.orderRef, E(110));
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(110));
      expect((await f.escrow.getOrder(q.orderRef)).status).to.equal(Status.Refunded);
      await f.escrow.connect(f.buyer).withdrawRefund();
      expect(await f.escrow.totalHeld()).to.equal(0);
    });

    it("refundUnshipped after 7 days, anyone can call", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      await expect(f.escrow.refundUnshipped(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increase(7 * DAY);
      await f.escrow.connect(f.other).refundUnshipped(q.orderRef);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(110));
    });
  });

  // ----------------------------------------------------------------- delivery adjustment
  describe("delivery adjustment", function () {
    it("lower delivery refunds buyer immediately", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      const before = await f.token.balanceOf(f.buyer.address);
      await expect(f.escrow.connect(f.seller).proposeDeliveryAdjustment(q.orderRef, E(4), H("why")))
        .to.emit(f.escrow, "DeliveryReductionRefunded").withArgs(q.orderRef, f.buyer.address, E(6));
      expect(await f.token.balanceOf(f.buyer.address)).to.equal(before + E(6));
      const o = await f.escrow.getOrder(q.orderRef);
      expect(o.deliveryAmount).to.equal(E(4));
      expect(o.status).to.equal(Status.Paid);
      expect(await f.escrow.totalHeld()).to.equal(E(104));
      await expect(f.escrow.connect(f.seller).proposeDeliveryAdjustment(q.orderRef, E(3), H("x")))
        .to.be.revertedWithCustomError(f.escrow, "AdjustmentAlreadyUsed");
    });

    it("higher delivery: buyer accepts and pays the difference, ship window resets", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      await expect(f.escrow.connect(f.seller).proposeDeliveryAdjustment(q.orderRef, E(10), H("x")))
        .to.be.revertedWithCustomError(f.escrow, "InvalidAmount");
      await f.escrow.connect(f.seller).proposeDeliveryAdjustment(q.orderRef, E(25), H("heavier"));
      expect((await f.escrow.getOrder(q.orderRef)).status).to.equal(Status.AdjustmentProposed);
      await expect(f.ship(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "WrongStatus");
      await expect(f.escrow.connect(f.other).acceptDeliveryAdjustment(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "NotBuyer");
      await time.increase(3 * DAY);
      await f.escrow.connect(f.buyer).acceptDeliveryAdjustment(q.orderRef);
      const o = await f.escrow.getOrder(q.orderRef);
      expect(o.deliveryAmount).to.equal(E(25));
      expect(o.status).to.equal(Status.Paid);
      expect(await f.escrow.totalHeld()).to.equal(E(125));
      expect(o.shipDeadline).to.be.gt(o.paidAt + BigInt(9 * DAY)); // reset from acceptance time
      await f.ship(q.orderRef);
    });

    it("buyer declines: full refund", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      await f.escrow.connect(f.seller).proposeDeliveryAdjustment(q.orderRef, E(25), H("x"));
      await f.escrow.connect(f.buyer).declineDeliveryAdjustment(q.orderRef);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(110));
    });

    it("unanswered proposal expires after 5 days: full refund; cannot accept after", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      await f.escrow.connect(f.seller).proposeDeliveryAdjustment(q.orderRef, E(25), H("x"));
      await expect(f.escrow.expireDeliveryAdjustment(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increase(5 * DAY);
      await expect(f.escrow.connect(f.buyer).acceptDeliveryAdjustment(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooLate");
      await f.escrow.connect(f.other).expireDeliveryAdjustment(q.orderRef);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(110));
    });

    it("seller can cancel during an open proposal; cannot propose after ship deadline", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      await f.escrow.connect(f.seller).proposeDeliveryAdjustment(q.orderRef, E(25), H("x"));
      await f.escrow.connect(f.seller).cancelBySeller(q.orderRef);
      expect((await f.escrow.getOrder(q.orderRef)).status).to.equal(Status.Refunded);

      const q2 = await f.pay({ orderRef: ref("o2") });
      await time.increase(7 * DAY);
      await expect(f.escrow.connect(f.seller).proposeDeliveryAdjustment(q2.orderRef, E(25), H("x")))
        .to.be.revertedWithCustomError(f.escrow, "TooLate");
    });
  });

  // ----------------------------------------------------------------- disputes
  describe("disputes", function () {
    it("only buyer, only while shipped and before release", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      await expect(f.escrow.connect(f.buyer).openDispute(q.orderRef, H("r"))).to.be.revertedWithCustomError(f.escrow, "WrongStatus");
      await f.ship(q.orderRef);
      await expect(f.escrow.connect(f.other).openDispute(q.orderRef, H("r"))).to.be.revertedWithCustomError(f.escrow, "NotBuyer");
      await time.increase(14 * DAY);
      await expect(f.escrow.connect(f.buyer).openDispute(q.orderRef, H("r"))).to.be.revertedWithCustomError(f.escrow, "TooLate");
    });

    it("buyer withdraws: seller paid", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await expect(f.escrow.connect(f.buyer).withdrawDispute(q.orderRef)).to.emit(f.escrow, "DisputeWithdrawn");
      expect(await f.escrow.balances(f.seller.address)).to.equal(E(108));
    });

    it("seller concedes: buyer fully refunded, no commission", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await expect(f.escrow.connect(f.other).concedeDispute(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "NotSeller");
      await f.escrow.connect(f.seller).concedeDispute(q.orderRef);
      const o = await f.escrow.getOrder(q.orderRef);
      expect(o.status).to.equal(Status.Refunded);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(110));
      expect(await f.escrow.balances(f.treasury.address)).to.equal(0);
    });

    it("owner resolves with a split; commission only on retained product", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await expect(f.escrow.connect(f.other).resolveDispute(q.orderRef, 0, 0)).to.be.revertedWithCustomError(f.escrow, "OwnableUnauthorizedAccount");
      await expect(f.escrow.resolveDispute(q.orderRef, E(101), 0)).to.be.revertedWithCustomError(f.escrow, "InvalidAmount");
      await expect(f.escrow.resolveDispute(q.orderRef, 0, E(11))).to.be.revertedWithCustomError(f.escrow, "InvalidAmount");
      // refund 40 product, 0 delivery: seller product 60 -> commission 1.2; seller gets 60+10-1.2=68.8
      await f.escrow.resolveDispute(q.orderRef, E(40), 0);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(40));
      expect(await f.escrow.balances(f.seller.address)).to.equal(E("68.8"));
      expect(await f.escrow.balances(f.treasury.address)).to.equal(E("1.2"));
      const { bal, owed } = await expectSolvent(f, [f.buyer.address, f.seller.address, f.treasury.address]);
      expect(owed).to.equal(bal);
    });

    it("owner extends once; cannot resolve after deadline", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await expect(f.escrow.connect(f.other).extendDispute(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "OwnableUnauthorizedAccount");
      const before = (await f.escrow.getOrder(q.orderRef)).disputeDeadline;
      await f.escrow.extendDispute(q.orderRef);
      expect((await f.escrow.getOrder(q.orderRef)).disputeDeadline).to.equal(before + BigInt(14 * DAY));
      await expect(f.escrow.extendDispute(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "AlreadyExtended");
      await time.increase(28 * DAY);
      await expect(f.escrow.resolveDispute(q.orderRef, 0, 0)).to.be.revertedWithCustomError(f.escrow, "TooLate");
    });

    it("expired dispute: full product refund, delivery refunded too (seller pays default)", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await expect(f.escrow.resolveExpiredDispute(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increase(14 * DAY);
      await f.escrow.connect(f.other).resolveExpiredDispute(q.orderRef);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(110));
    });
  });

  // ----------------------------------------------------------------- returns
  describe("returns", function () {
    const cost = E(5);

    it("seller-fault return: seller funds from wallet, buyer ships, seller confirms", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await expect(f.escrow.connect(f.other).approveReturn(q.orderRef, Reason.Defective, cost)).to.be.revertedWithCustomError(f.escrow, "OwnableUnauthorizedAccount");
      await expect(f.escrow.approveReturn(q.orderRef, Reason.None, cost)).to.be.revertedWithCustomError(f.escrow, "InvalidReturnReason");
      await expect(f.escrow.approveReturn(q.orderRef, Reason.WrongAddress, cost)).to.be.revertedWithCustomError(f.escrow, "InvalidReturnReason");
      await expect(f.escrow.approveReturn(q.orderRef, Reason.Defective, E(101))).to.be.revertedWithCustomError(f.escrow, "InvalidAmount");
      await f.escrow.approveReturn(q.orderRef, Reason.Defective, cost);
      expect((await f.escrow.getOrder(q.orderRef)).status).to.equal(Status.ReturnApproved);
      await expect(f.escrow.approveReturn(q.orderRef, Reason.Defective, cost)).to.be.revertedWithCustomError(f.escrow, "WrongStatus");

      await expect(f.escrow.connect(f.buyer).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest()))
        .to.be.revertedWithCustomError(f.escrow, "ReturnNotFunded");
      await expect(f.escrow.connect(f.other).fundReturnPostage(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "NotSeller");
      await f.escrow.connect(f.seller).fundReturnPostage(q.orderRef);
      await expect(f.escrow.connect(f.seller).fundReturnPostage(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "AlreadyFunded");
      expect(await f.escrow.totalHeld()).to.equal(E(115));

      await expect(f.escrow.connect(f.other).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest()))
        .to.be.revertedWithCustomError(f.escrow, "NotBuyer");
      await f.escrow.connect(f.buyer).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest());
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(cost); // postage reimbursed

      await f.escrow.connect(f.seller).confirmReturnReceived(q.orderRef);
      expect((await f.escrow.getOrder(q.orderRef)).status).to.equal(Status.Refunded);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(115));
      expect(await f.escrow.balances(f.seller.address)).to.equal(0);
      const { bal, owed } = await expectSolvent(f, [f.buyer.address, f.seller.address, f.treasury.address]);
      expect(owed).to.equal(bal);
    });

    it("fundReturnPostage uses seller earnings first", async function () {
      const f = await loadFixture(deploy);
      const first = await f.payAndShip({ orderRef: ref("earn"), productAmount: E(100), deliveryAmount: 0 });
      await f.escrow.connect(f.buyer).confirmReceipt(first.orderRef); // seller balance 98
      const q = await f.payShipDispute({ orderRef: ref("ret") });
      await f.escrow.approveReturn(q.orderRef, Reason.WrongItem, cost);
      const walletBefore = await f.token.balanceOf(f.seller.address);
      await expect(f.escrow.connect(f.seller).fundReturnPostage(q.orderRef))
        .to.emit(f.escrow, "ReturnPostageFunded");
      expect(await f.token.balanceOf(f.seller.address)).to.equal(walletBefore); // nothing pulled
      expect(await f.escrow.balances(f.seller.address)).to.equal(E(98) - cost);
    });

    it("fund window expires: ReturnForfeited -> full refund", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await f.escrow.approveReturn(q.orderRef, Reason.Defective, cost);
      await expect(f.escrow.finalizeReturn(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increase(3 * DAY);
      await expect(f.escrow.connect(f.seller).fundReturnPostage(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooLate");
      await expect(f.escrow.finalizeReturn(q.orderRef)).to.emit(f.escrow, "ReturnForfeited");
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(110));
    });

    it("buyer never ships back: abandoned -> normal sale, postage returned to seller", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await f.escrow.approveReturn(q.orderRef, Reason.Defective, cost);
      await f.escrow.connect(f.seller).fundReturnPostage(q.orderRef);
      await time.increase(7 * DAY);
      await expect(f.escrow.finalizeReturn(q.orderRef)).to.emit(f.escrow, "ReturnAbandoned");
      // seller: 110 - commission 2 + 5 postage back
      expect(await f.escrow.balances(f.seller.address)).to.equal(E(108) + cost);
      const { bal, owed } = await expectSolvent(f, [f.buyer.address, f.seller.address, f.treasury.address]);
      expect(owed).to.equal(bal);
    });

    it("changed mind: buyer pays postage, product refunded, seller keeps delivery", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await expect(f.escrow.approveReturn(q.orderRef, Reason.ChangedMind, cost)).to.be.revertedWithCustomError(f.escrow, "InvalidAmount");
      await f.escrow.approveReturn(q.orderRef, Reason.ChangedMind, 0);
      await f.escrow.connect(f.buyer).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest());
      await f.escrow.connect(f.seller).confirmReturnReceived(q.orderRef);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(100));
      expect(await f.escrow.balances(f.seller.address)).to.equal(E(10));
      expect((await f.escrow.getOrder(q.orderRef)).status).to.equal(Status.Completed);
    });

    it("seller does not respond to a shipped return: finalize refunds buyer", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await f.escrow.approveReturn(q.orderRef, Reason.ChangedMind, 0);
      await f.escrow.connect(f.buyer).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest());
      await expect(f.escrow.finalizeReturn(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increase(14 * DAY);
      await expect(f.escrow.connect(f.seller).contestReturn(q.orderRef, H("x"))).to.be.revertedWithCustomError(f.escrow, "TooLate");
      await expect(f.escrow.finalizeReturn(q.orderRef)).to.emit(f.escrow, "ReturnCompleted");
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(100));
    });

    it("seller contests: back to Disputed with fresh deadline; owner can resolve", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await f.escrow.approveReturn(q.orderRef, Reason.ChangedMind, 0);
      await f.escrow.connect(f.buyer).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest());
      await expect(f.escrow.connect(f.other).contestReturn(q.orderRef, H("x"))).to.be.revertedWithCustomError(f.escrow, "NotSeller");
      await f.escrow.connect(f.seller).contestReturn(q.orderRef, H("empty box"));
      expect((await f.escrow.getOrder(q.orderRef)).status).to.equal(Status.Disputed);
      // buyer can no longer withdraw the dispute after a return decision
      await expect(f.escrow.connect(f.buyer).withdrawDispute(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "ReturnAlreadyDecided");
      await expect(f.escrow.approveReturn(q.orderRef, Reason.Defective, cost)).to.be.revertedWithCustomError(f.escrow, "ReturnAlreadyDecided");
      await f.escrow.resolveDispute(q.orderRef, 0, 0); // seller wins
      expect((await f.escrow.getOrder(q.orderRef)).status).to.equal(Status.Completed);
    });

    it("wrong address: cost deducted from refund, paid to seller", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await expect(f.escrow.connect(f.other).resolveWrongAddress(q.orderRef, cost)).to.be.revertedWithCustomError(f.escrow, "OwnableUnauthorizedAccount");
      await expect(f.escrow.resolveWrongAddress(q.orderRef, E(101))).to.be.revertedWithCustomError(f.escrow, "InvalidAmount");
      await expect(f.escrow.resolveWrongAddress(q.orderRef, cost))
        .to.emit(f.escrow, "WrongAddressResolved").withArgs(q.orderRef, cost, E(95), E(15));
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(95));
      expect(await f.escrow.balances(f.seller.address)).to.equal(E(15));
      const { bal, owed } = await expectSolvent(f, [f.buyer.address, f.seller.address]);
      expect(owed).to.equal(bal);
    });
  });

  // ----------------------------------------------------------------- owner / admin
  describe("admin", function () {
    it("fee change: 48h timelock, applies to new orders only, old orders keep snapshot", async function () {
      const f = await loadFixture(deploy);
      const old = await f.payAndShip();
      await expect(f.escrow.connect(f.other).proposeFeeConfig(300, 0, 0)).to.be.revertedWithCustomError(f.escrow, "OwnableUnauthorizedAccount");
      await expect(f.escrow.proposeFeeConfig(1001, 0, 0)).to.be.revertedWithCustomError(f.escrow, "InvalidFeeConfig");
      await expect(f.escrow.proposeFeeConfig(300, 6000, 5000)).to.be.revertedWithCustomError(f.escrow, "InvalidFeeConfig");
      await f.escrow.proposeFeeConfig(500, 1000, 1000);
      await expect(f.escrow.executeFeeConfig()).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increase(48 * HOUR);
      await f.escrow.connect(f.other).executeFeeConfig();
      expect((await f.escrow.feeConfig()).feeBps).to.equal(500);
      await expect(f.escrow.executeFeeConfig()).to.be.revertedWithCustomError(f.escrow, "NoPendingFeeConfig");

      // old quote fee no longer valid
      const stale = await f.makeQuote({ orderRef: ref("stale") });
      await expect(f.escrow.connect(f.buyer).createOrder(stale, await f.sign(stale))).to.be.revertedWithCustomError(f.escrow, "FeeMismatch");
      // old order keeps the 2% snapshot
      await f.escrow.connect(f.buyer).confirmReceipt(old.orderRef);
      expect(await f.escrow.balances(f.treasury.address)).to.equal(E(2));
      // new order uses 5%
      const nq = await f.payAndShip({ orderRef: ref("new"), feeBps: 500 });
      await f.escrow.connect(f.buyer).confirmReceipt(nq.orderRef);
      expect(await f.escrow.balances(f.treasury.address)).to.equal(E(2) + E(5));
    });

    it("fee change can be cancelled", async function () {
      const f = await loadFixture(deploy);
      await expect(f.escrow.cancelFeeConfig()).to.be.revertedWithCustomError(f.escrow, "NoPendingFeeConfig");
      await f.escrow.proposeFeeConfig(500, 0, 0);
      await f.escrow.cancelFeeConfig();
      await time.increase(48 * HOUR);
      await expect(f.escrow.executeFeeConfig()).to.be.revertedWithCustomError(f.escrow, "NoPendingFeeConfig");
    });

    it("pause stops new orders but not exits", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payAndShip();
      await f.escrow.pause();
      await f.escrow.connect(f.buyer).confirmReceipt(q.orderRef);
      await f.escrow.connect(f.seller).withdraw();
      await expect(f.escrow.connect(f.other).pause()).to.be.revertedWithCustomError(f.escrow, "OwnableUnauthorizedAccount");
    });

    it("operator/treasury setters", async function () {
      const f = await loadFixture(deploy);
      await expect(f.escrow.setOperator(ZERO)).to.be.revertedWithCustomError(f.escrow, "ZeroAddress");
      await expect(f.escrow.setTreasury(ZERO)).to.be.revertedWithCustomError(f.escrow, "ZeroAddress");
      await expect(f.escrow.connect(f.other).setOperator(f.other.address)).to.be.revertedWithCustomError(f.escrow, "OwnableUnauthorizedAccount");
      await f.escrow.setOperator(f.other.address);
      const q = await f.makeQuote();
      await expect(f.escrow.connect(f.buyer).createOrder(q, await f.sign(q))).to.be.revertedWithCustomError(f.escrow, "BadSignature");
      await f.escrow.connect(f.buyer).createOrder(q, await f.sign(q, f.other));
      await f.escrow.setTreasury(f.referrer.address);
      expect(await f.escrow.treasury()).to.equal(f.referrer.address);
    });

    it("ownership is two-step and renounce is disabled", async function () {
      const f = await loadFixture(deploy);
      await expect(f.escrow.renounceOwnership()).to.be.revertedWithCustomError(f.escrow, "RenounceDisabled");
      await f.escrow.transferOwnership(f.other.address);
      expect(await f.escrow.owner()).to.equal(f.owner.address);
      await f.escrow.connect(f.other).acceptOwnership();
      expect(await f.escrow.owner()).to.equal(f.other.address);
    });

    it("rescueExcess only sweeps tokens beyond totalHeld", async function () {
      const f = await loadFixture(deploy);
      await f.pay();
      await expect(f.escrow.rescueExcess()).to.be.revertedWithCustomError(f.escrow, "NothingToWithdraw");
      await f.token.connect(f.other).transfer(f.escrowAddr, E(7)); // mistaken transfer
      await expect(f.escrow.connect(f.other).rescueExcess()).to.be.revertedWithCustomError(f.escrow, "OwnableUnauthorizedAccount");
      await expect(f.escrow.rescueExcess()).to.emit(f.escrow, "ExcessRescued").withArgs(E(7));
      expect(await f.token.balanceOf(f.treasury.address)).to.equal(E(7));
      expect(await f.token.balanceOf(f.escrowAddr)).to.equal(E(110)); // user funds untouched
    });
  });

  // ----------------------------------------------------------------- end-to-end solvency
  describe("solvency across many orders", function () {
    it("every token leaves exactly once", async function () {
      const f = await loadFixture(deploy);
      const all = [f.buyer, f.seller, f.referrer, f.treasury, f.other].map((s) => s.address);
      await f.escrow.connect(f.operator).setVerified(f.referrer.address, true);
      await f.escrow.connect(f.operator).setVerified(f.buyer.address, true);

      const a = await f.payAndShip({ orderRef: ref("a"), referrer: f.referrer.address, productAmount: E(1000), deliveryAmount: E(20) });
      const b = await f.payAndShip({ orderRef: ref("b"), referrer: f.referrer.address, productAmount: E(333), deliveryAmount: E("7.77") });
      const c = await f.pay({ orderRef: ref("c"), referrer: f.referrer.address, productAmount: E(50), deliveryAmount: E(5) });
      const d = await f.payShipDispute({ orderRef: ref("d"), referrer: f.referrer.address, productAmount: E(200), deliveryAmount: E(15) });

      await f.escrow.connect(f.buyer).confirmReceipt(a.orderRef);
      await f.escrow.connect(f.buyer).confirmReceipt(b.orderRef);
      await f.escrow.connect(f.seller).cancelBySeller(c.orderRef);
      await f.escrow.resolveDispute(d.orderRef, E("77.7"), E(3));

      const { bal, owed } = await expectSolvent(f, all);
      expect(owed).to.equal(bal);

      for (const s of [f.buyer, f.seller, f.treasury]) {
        if ((await f.escrow.refunds(s.address)) > 0n) await f.escrow.connect(s).withdrawRefund();
        if ((await f.escrow.balances(s.address)) > 0n) await f.escrow.connect(s).withdraw();
      }
      await f.escrow.connect(f.referrer).withdrawRewards();
      await f.escrow.connect(f.buyer).withdrawRewards();
      expect(await f.escrow.totalHeld()).to.equal(0);
      expect(await f.token.balanceOf(f.escrowAddr)).to.equal(0);
    });
  });

  // ----------------------------------------------------------------- workflow spec
  // Rules from documents/PLEXUS-Order-Workflow.pdf that the sections above do not pin down:
  // the spec's own numbers, exact deadline boundaries, and the long / contested paths.
  describe("workflow spec", function () {
    const sellerBalance = (f) => f.escrow.balances(f.seller.address);

    it("example: $100 + $15 with a referrer -> seller $113, referrer $0.60, buyer $0.40, PLEXUS $1.00", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payAndShip({ deliveryAmount: E(15), referrer: f.referrer.address });
      await f.escrow.connect(f.buyer).confirmReceipt(q.orderRef);
      expect(await sellerBalance(f)).to.equal(E(113));
      expect(await f.escrow.rewards(f.referrer.address)).to.equal(E("0.6"));
      expect(await f.escrow.rewards(f.buyer.address)).to.equal(E("0.4"));
      expect(await f.escrow.balances(f.treasury.address)).to.equal(E(1));
    });

    it("example: wrong address with a $12 return cost -> buyer $88, seller $27, no commission", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute({ deliveryAmount: E(15) });
      await f.escrow.resolveWrongAddress(q.orderRef, E(12));
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(88));
      expect(await sellerBalance(f)).to.equal(E(27));
      expect(await f.escrow.balances(f.treasury.address)).to.equal(0);
    });

    it("example: seller-fault return with $8 postage -> buyer $123, seller $0 and pays the $8", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute({ deliveryAmount: E(15) });
      await f.escrow.approveReturn(q.orderRef, Reason.Defective, E(8));
      const walletBefore = await f.token.balanceOf(f.seller.address);
      await f.escrow.connect(f.seller).fundReturnPostage(q.orderRef);
      expect(walletBefore - (await f.token.balanceOf(f.seller.address))).to.equal(E(8));
      await f.escrow.connect(f.buyer).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest());
      await f.escrow.connect(f.seller).confirmReturnReceived(q.orderRef);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(123));
      expect(await sellerBalance(f)).to.equal(0);
    });

    it("rounding: every wei is accounted for and the dust stays with PLEXUS", async function () {
      const f = await loadFixture(deploy);
      const product = 1000000000000000007n, delivery = 3n;
      const q = await f.payAndShip({ productAmount: product, deliveryAmount: delivery, referrer: f.referrer.address });
      await f.escrow.connect(f.buyer).confirmReceipt(q.orderRef);
      const credits =
        (await sellerBalance(f)) + (await f.escrow.rewards(f.referrer.address)) +
        (await f.escrow.rewards(f.buyer.address)) + (await f.escrow.balances(f.treasury.address));
      expect(credits).to.equal(product + delivery);
    });

    it("release timer starts at shipping: a backdated date cannot shorten it (14d domestic, 30d international)", async function () {
      const f = await loadFixture(deploy);
      for (const [international, days] of [[false, 14], [true, 30]]) {
        const q = await f.pay({ orderRef: ref(`backdate-${days}`), international });
        const paidAt = (await f.escrow.getOrder(q.orderRef)).paidAt;
        await time.increase(3 * DAY);
        await f.escrow.connect(f.seller).markShipped(q.orderRef, H("DHL"), H("T"), H("p"), paidAt);
        const o = await f.escrow.getOrder(q.orderRef);
        expect(o.shippedAt).to.equal(paidAt);
        expect(o.releaseAt).to.equal(BigInt(await time.latest()) + BigInt(days * DAY));
      }
    });

    it("every deadline flips exactly on time: one second early is refused, on time works", async function () {
      const f = await loadFixture(deploy);
      const get = (r) => f.escrow.getOrder(r);

      // 7-day shipping deadline: refundUnshipped
      let q = await f.pay({ orderRef: ref("t-ship") });
      let d = (await get(q.orderRef)).shipDeadline;
      await time.increaseTo(d - 3n);
      await expect(f.escrow.refundUnshipped(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increaseTo(d - 1n);
      await f.escrow.refundUnshipped(q.orderRef);

      // release timer
      q = await f.payAndShip({ orderRef: ref("t-release") });
      d = (await get(q.orderRef)).releaseAt;
      await time.increaseTo(d - 3n);
      await expect(f.escrow.release(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increaseTo(d - 1n);
      await f.escrow.release(q.orderRef);

      // 5-day answer window for a delivery change
      q = await f.pay({ orderRef: ref("t-adjust") });
      await f.escrow.connect(f.seller).proposeDeliveryAdjustment(q.orderRef, E(30), H("x"));
      d = (await get(q.orderRef)).adjustmentDeadline;
      await time.increaseTo(d - 3n);
      await expect(f.escrow.expireDeliveryAdjustment(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increaseTo(d - 1n);
      await f.escrow.expireDeliveryAdjustment(q.orderRef);

      // 14-day dispute window: team can decide up to the deadline, anyone refunds from it
      q = await f.payShipDispute({ orderRef: ref("t-dispute-a") });
      d = (await get(q.orderRef)).disputeDeadline;
      await time.increaseTo(d - 3n);
      await expect(f.escrow.resolveExpiredDispute(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await f.escrow.resolveDispute(q.orderRef, 0, 0); // still allowed one second before
      q = await f.payShipDispute({ orderRef: ref("t-dispute-b") });
      d = (await get(q.orderRef)).disputeDeadline;
      await time.increaseTo(d - 1n);
      await expect(f.escrow.resolveDispute(q.orderRef, 0, 0)).to.be.revertedWithCustomError(f.escrow, "TooLate");
      await f.escrow.resolveExpiredDispute(q.orderRef);

      // 3-day postage deposit window
      q = await f.payShipDispute({ orderRef: ref("t-fund") });
      await f.escrow.approveReturn(q.orderRef, Reason.Defective, E(8));
      d = (await get(q.orderRef)).returnDeadline;
      await time.increaseTo(d - 3n);
      await expect(f.escrow.finalizeReturn(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increaseTo(d - 1n);
      await f.escrow.finalizeReturn(q.orderRef);
    });

    it("dispute: team extends once to 28 days and can still decide after the original deadline", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute({ orderRef: ref("ext-a") });
      const d0 = (await f.escrow.getOrder(q.orderRef)).disputeDeadline;
      await f.escrow.extendDispute(q.orderRef);
      await time.increaseTo(d0 + 60n); // past the original deadline
      await expect(f.escrow.resolveExpiredDispute(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await f.escrow.resolveDispute(q.orderRef, 0, 0);
      expect((await f.escrow.getOrder(q.orderRef)).status).to.equal(Status.Completed);

      // too late to extend once the original deadline has passed
      const q2 = await f.payShipDispute({ orderRef: ref("ext-b") });
      await time.increase(14 * DAY + 60);
      await expect(f.escrow.extendDispute(q2.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooLate");
    });

    it("international return: the seller has 30 days (not 14) to confirm or contest", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute({ international: true });
      await f.escrow.approveReturn(q.orderRef, Reason.ChangedMind, 0);
      await f.escrow.connect(f.buyer).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest());
      await time.increase(14 * DAY + 60);
      await expect(f.escrow.finalizeReturn(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "TooEarly");
      await time.increase(16 * DAY);
      await f.escrow.finalizeReturn(q.orderRef);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(100));
    });

    it("seller contests a return and the team stays silent: the normal outcome for the reason applies", async function () {
      const f = await loadFixture(deploy);
      // changed mind: buyer $100, seller keeps delivery $15
      let q = await f.payShipDispute({ orderRef: ref("silent-a"), deliveryAmount: E(15) });
      await f.escrow.approveReturn(q.orderRef, Reason.ChangedMind, 0);
      await f.escrow.connect(f.buyer).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest());
      await f.escrow.connect(f.seller).contestReturn(q.orderRef, H("empty box"));
      await time.increase(14 * DAY + 60);
      await f.escrow.resolveExpiredDispute(q.orderRef);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(100));
      expect(await sellerBalance(f)).to.equal(E(15));
      await f.escrow.connect(f.buyer).withdrawRefund();

      // seller at fault: buyer $115 + $8 postage
      q = await f.payShipDispute({ orderRef: ref("silent-b"), deliveryAmount: E(15) });
      await f.escrow.approveReturn(q.orderRef, Reason.Defective, E(8));
      await f.escrow.connect(f.seller).fundReturnPostage(q.orderRef);
      await f.escrow.connect(f.buyer).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest());
      await f.escrow.connect(f.seller).contestReturn(q.orderRef, H("not what I sent"));
      await time.increase(14 * DAY + 60);
      await f.escrow.resolveExpiredDispute(q.orderRef);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(123));
    });
  });

  // ----------------------------------------------------------------- guards and edge cases
  describe("guards and edge cases", function () {
    it("every call made in the wrong order status is refused", async function () {
      const f = await loadFixture(deploy);
      const e = f.escrow;
      const bad = (call, name = "WrongStatus") => expect(call).to.be.revertedWithCustomError(e, name);
      const paid = (await f.pay({ orderRef: ref("g-paid") })).orderRef;
      const shipped = (await f.payAndShip({ orderRef: ref("g-ship") })).orderRef;
      const proposed = (await f.pay({ orderRef: ref("g-prop") })).orderRef;
      await e.connect(f.seller).proposeDeliveryAdjustment(proposed, E(30), H("x"));
      const noop = [H("c"), H("t"), H("p"), 0];

      // a Paid order has no adjustment, dispute or return to act on
      await bad(e.connect(f.buyer).acceptDeliveryAdjustment(paid));
      await bad(e.connect(f.buyer).declineDeliveryAdjustment(paid));
      await bad(e.expireDeliveryAdjustment(paid));
      await bad(e.release(paid));
      await bad(e.connect(f.buyer).withdrawDispute(paid));
      await bad(e.connect(f.seller).concedeDispute(paid));
      await bad(e.extendDispute(paid));
      await bad(e.resolveDispute(paid, 0, 0));
      await bad(e.resolveExpiredDispute(paid));
      await bad(e.approveReturn(paid, Reason.Defective, E(1)));
      await bad(e.resolveWrongAddress(paid, 0));
      await bad(e.connect(f.seller).fundReturnPostage(paid));
      await bad(e.connect(f.buyer).markReturnShipped(paid, ...noop));
      await bad(e.connect(f.seller).confirmReturnReceived(paid));
      await bad(e.connect(f.seller).contestReturn(paid, H("x")));
      await bad(e.finalizeReturn(paid));

      // a Shipped order can no longer be cancelled, refunded unshipped or re-priced
      await bad(e.connect(f.seller).cancelBySeller(shipped));
      await bad(e.refundUnshipped(shipped));
      await bad(e.connect(f.seller).proposeDeliveryAdjustment(shipped, E(1), H("x")));
      await bad(e.connect(f.buyer).acceptDeliveryAdjustment(shipped));

      // an open proposal blocks the unshipped refund
      await bad(e.refundUnshipped(proposed));

      // wrong caller
      await bad(e.connect(f.other).proposeDeliveryAdjustment(paid, E(1), H("x")), "NotSeller");
      await bad(e.connect(f.other).declineDeliveryAdjustment(proposed), "NotBuyer");
      await bad(e.connect(f.other).acceptDeliveryAdjustment(proposed), "NotBuyer");
    });

    it("owner-only functions refuse everyone else", async function () {
      const f = await loadFixture(deploy);
      const bad = (call) => expect(call).to.be.revertedWithCustomError(f.escrow, "OwnableUnauthorizedAccount");
      await bad(f.escrow.connect(f.other).setTreasury(f.other.address));
      await bad(f.escrow.connect(f.other).unpause());
      await bad(f.escrow.connect(f.other).cancelFeeConfig());
      await bad(f.escrow.connect(f.other).extendDispute(ref("x")));
      await bad(f.escrow.connect(f.operator).pause());
    });

    it("dispute actions need the right person", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await expect(f.escrow.connect(f.other).withdrawDispute(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "NotBuyer");
      await f.escrow.approveReturn(q.orderRef, Reason.ChangedMind, 0);
      await f.escrow.connect(f.buyer).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest());
      await expect(f.escrow.connect(f.other).confirmReturnReceived(q.orderRef)).to.be.revertedWithCustomError(f.escrow, "NotSeller");
    });

    it("a contested return cannot be turned into a wrong-address decision", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await f.escrow.approveReturn(q.orderRef, Reason.ChangedMind, 0);
      await f.escrow.connect(f.buyer).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest());
      await f.escrow.connect(f.seller).contestReturn(q.orderRef, H("x"));
      await expect(f.escrow.resolveWrongAddress(q.orderRef, 0)).to.be.revertedWithCustomError(f.escrow, "ReturnAlreadyDecided");
    });

    it("the team cannot approve a return or decide wrong-address after the dispute deadline", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await time.increase(14 * DAY + 60);
      await expect(f.escrow.approveReturn(q.orderRef, Reason.Defective, E(1))).to.be.revertedWithCustomError(f.escrow, "TooLate");
      await expect(f.escrow.resolveWrongAddress(q.orderRef, 0)).to.be.revertedWithCustomError(f.escrow, "TooLate");
    });

    it("the buyer cannot ship the return after the 7-day window", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await f.escrow.approveReturn(q.orderRef, Reason.ChangedMind, 0);
      await time.increase(7 * DAY + 60);
      await expect(f.escrow.connect(f.buyer).markReturnShipped(q.orderRef, H("c"), H("t"), H("p"), await time.latest()))
        .to.be.revertedWithCustomError(f.escrow, "TooLate");
    });

    it("wrong address with no return cost and no delivery: buyer refunded in full, order Refunded", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute({ deliveryAmount: 0 });
      await f.escrow.resolveWrongAddress(q.orderRef, 0);
      expect((await f.escrow.getOrder(q.orderRef)).status).to.equal(Status.Refunded);
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(E(100));
    });

    it("wrong address where the return cost eats the whole product price: seller gets it all", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute({ deliveryAmount: 0 });
      await f.escrow.resolveWrongAddress(q.orderRef, E(100));
      expect(await f.escrow.refunds(f.buyer.address)).to.equal(0);
      expect(await f.escrow.balances(f.seller.address)).to.equal(E(100));
      expect((await f.escrow.getOrder(q.orderRef)).status).to.equal(Status.Completed);
    });

    it("buyer never ships back a free return (cost 0): seller is paid as normal", async function () {
      const f = await loadFixture(deploy);
      const q = await f.payShipDispute();
      await f.escrow.approveReturn(q.orderRef, Reason.ChangedMind, 0);
      await time.increase(7 * DAY + 60);
      await expect(f.escrow.finalizeReturn(q.orderRef)).to.emit(f.escrow, "ReturnAbandoned");
      expect(await f.escrow.balances(f.seller.address)).to.equal(E(108));
    });

    it("delivery fee reduced to zero: buyer refunded the whole fee, order still settles", async function () {
      const f = await loadFixture(deploy);
      const q = await f.pay();
      const before = await f.token.balanceOf(f.buyer.address);
      await f.escrow.connect(f.seller).proposeDeliveryAdjustment(q.orderRef, 0, H("free shipping"));
      expect((await f.token.balanceOf(f.buyer.address)) - before).to.equal(E(10));
      await f.ship(q.orderRef);
      await f.escrow.connect(f.buyer).confirmReceipt(q.orderRef);
      expect(await f.escrow.balances(f.seller.address)).to.equal(E(98));
    });

    it("someone who is both a buyer and a seller keeps refunds and earnings separate", async function () {
      const f = await loadFixture(deploy);
      const both = f.other;
      // as a seller: earns 108
      const sale = await f.pay({ orderRef: ref("both-sale"), seller: both.address });
      await f.ship(sale.orderRef, both);
      await f.escrow.connect(f.buyer).confirmReceipt(sale.orderRef);
      // as a buyer: a cancelled purchase refunds 55
      const buy = await f.pay({ orderRef: ref("both-buy"), buyer: both.address, productAmount: E(50), deliveryAmount: E(5) }, both);
      await f.escrow.connect(f.seller).cancelBySeller(buy.orderRef);
      expect(await f.escrow.balances(both.address)).to.equal(E(108));
      expect(await f.escrow.refunds(both.address)).to.equal(E(55));
      await f.escrow.connect(both).withdrawRefund();
      expect(await f.escrow.balances(both.address)).to.equal(E(108)); // earnings untouched
      await f.escrow.connect(both).withdraw();
      expect(await f.escrow.balances(both.address)).to.equal(0);
    });

    it("a verified user with no rewards has nothing to withdraw", async function () {
      const f = await loadFixture(deploy);
      await f.escrow.connect(f.operator).setVerified(f.other.address, true);
      await expect(f.escrow.connect(f.other).withdrawRewards()).to.be.revertedWithCustomError(f.escrow, "NothingToWithdraw");
    });
  });
});
