const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");

// Helpers

const U = (n) => ethers.parseUnits(String(n), 18); // BSC-USD has 18 decimals
const DAY = 24 * 60 * 60;
const { ZeroAddress, ZeroHash } = ethers;

const Status = {
  None: 0, Paid: 1, AdjustmentProposed: 2, Shipped: 3, Disputed: 4,
  Completed: 5, Refunded: 6, ReturnApproved: 7, ReturnShipped: 8,
};
const Reason = {
  None: 0, NotAsDescribed: 1, WrongItem: 2, DamagedInTransit: 3,
  ChangedMind: 4, Defective: 5, WrongAddress: 6,
};

const CARRIER = ethers.encodeBytes32String("DHL");
const TRACKING = ethers.id("DHL:1234567890");
const PROOF = ethers.id("receipt-photo.jpg");
const RETURN_CARRIER = ethers.encodeBytes32String("FEDEX");
const RETURN_TRACKING = ethers.id("FEDEX:771234567890");
const REASON = ethers.id("item not as described");

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

let orderCounter = 0;

async function deployFixture() {
  // owner = PLEXUS Safe
  const [owner, operator, treasury, buyer, seller, referrer, other, newOwner] = await ethers.getSigners();

  const token = await (await ethers.getContractFactory("MockUSDT")).deploy();
  const escrow = await (await ethers.getContractFactory("PlexusEscrowV2")).deploy(
    token.target, owner.address, operator.address, treasury.address,
    200, // 2% commission
    3000, // 30% of commission to referrer
    2000, // 20% of commission to referred buyer
    U(5) // $5 minimum for seller earnings and rewards
  );

  for (const s of [buyer, seller, referrer, other]) {
    await token.mint(s.address, U(10_000));
    await token.connect(s).approve(escrow.target, ethers.MaxUint256);
  }

  const { chainId } = await ethers.provider.getNetwork();
  const domain = { name: "PlexusEscrow", version: "2", chainId, verifyingContract: escrow.target };

  return { token, escrow, domain, owner, operator, treasury, buyer, seller, referrer, other, newOwner };
}

// Builds and signs a quote with the operator key.
async function signQuote(ctx, opts = {}) {
  const {
    buyer = ctx.buyer, seller = ctx.seller, referrer = ZeroAddress,
    product = U(100), delivery = U(10), feeBps = 200, international = false,
  } = opts;
  const q = {
    orderRef: ethers.id(`order-${++orderCounter}`),
    buyer: buyer.address,
    seller: seller.address,
    referrer,
    productAmount: product,
    deliveryAmount: delivery,
    feeBps,
    international,
    validUntil: (await time.latest()) + 3 * DAY,
  };
  const sig = await ctx.operator.signTypedData(ctx.domain, QUOTE_TYPES, q);
  return { q, sig, buyer };
}

// Signs a quote and pays it from the buyer's wallet. Returns the orderRef.
async function placeOrder(ctx, opts = {}) {
  const { q, sig, buyer } = await signQuote(ctx, opts);
  await ctx.escrow.connect(buyer).createOrder(q, sig);
  return q.orderRef;
}

async function ship(ctx, ref, shippedAt, proof = ZeroHash) {
  shippedAt ??= await time.latest();
  return ctx.escrow.connect(ctx.seller).markShipped(ref, CARRIER, TRACKING, proof, shippedAt);
}

async function shipAndDispute(ctx, opts) {
  const ref = await placeOrder(ctx, opts);
  await ship(ctx, ref);
  await ctx.escrow.connect(ctx.buyer).openDispute(ref, REASON);
  return ref;
}

async function shipReturn(ctx, ref, shippedAt) {
  shippedAt ??= await time.latest();
  return ctx.escrow.connect(ctx.buyer).markReturnShipped(ref, RETURN_CARRIER, RETURN_TRACKING, ZeroHash, shippedAt);
}

async function blockTime(tx) {
  const receipt = await tx.wait();
  return (await ethers.provider.getBlock(receipt.blockNumber)).timestamp;
}

// The contract must always hold exactly what it owes.
async function expectSolvent(ctx) {
  expect(await ctx.token.balanceOf(ctx.escrow.target)).to.equal(await ctx.escrow.totalHeld());
}

// Tests

describe("PlexusEscrowV2", function () {
  // 1a. Shipping details
  describe("1a. Shipping: carrier, tracking number, date, optional proof", function () {
    it("rejects a zero carrier", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await expect(
        ctx.escrow.connect(ctx.seller).markShipped(ref, ZeroHash, TRACKING, ZeroHash, await time.latest())
      ).to.be.revertedWithCustomError(ctx.escrow, "InvalidShipment");
    });

    it("rejects a zero tracking hash", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await expect(
        ctx.escrow.connect(ctx.seller).markShipped(ref, CARRIER, ZeroHash, ZeroHash, await time.latest())
      ).to.be.revertedWithCustomError(ctx.escrow, "InvalidShipment");
    });

    it("rejects a shipping date in the future", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await expect(ship(ctx, ref, (await time.latest()) + DAY))
        .to.be.revertedWithCustomError(ctx.escrow, "InvalidShipment");
    });

    it("rejects a shipping date before payment", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      const { paidAt } = await ctx.escrow.getOrder(ref);
      await expect(ship(ctx, ref, paidAt - 1n))
        .to.be.revertedWithCustomError(ctx.escrow, "InvalidShipment");
    });

    it("records the shipment and emits carrier, tracking, proof and date", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      const shippedAt = await time.latest();
      await expect(ship(ctx, ref, shippedAt, PROOF))
        .to.emit(ctx.escrow, "Shipped").withArgs(ref, CARRIER, TRACKING, PROOF, shippedAt, anyValue);

      const o = await ctx.escrow.getOrder(ref);
      expect(o.status).to.equal(Status.Shipped);
      expect(o.shippedAt).to.equal(shippedAt);
    });

    it("proof of shipment is optional", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await ship(ctx, ref); // ZeroHash proof
      expect((await ctx.escrow.getOrder(ref)).status).to.equal(Status.Shipped);
    });

    it("starts the release window when recorded, so backdating cannot shorten it", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      const { paidAt } = await ctx.escrow.getOrder(ref);
      await time.increase(3 * DAY);

      const tx = await ship(ctx, ref, paidAt);
      const recordedAt = await blockTime(tx);
      expect((await ctx.escrow.getOrder(ref)).releaseAt).to.equal(BigInt(recordedAt + 14 * DAY));
    });

    it("only the seller can ship", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await expect(
        ctx.escrow.connect(ctx.other).markShipped(ref, CARRIER, TRACKING, ZeroHash, await time.latest())
      ).to.be.revertedWithCustomError(ctx.escrow, "NotSeller");
    });

    it("seller receives the delivery fee with no commission on it", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx, { product: U(100), delivery: U(25) });
      await ship(ctx, ref);
      await ctx.escrow.connect(ctx.buyer).confirmReceipt(ref);
      expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U(123)); // 100 - 2 + 25
    });
  });

  // 1b. Returns by reason
  describe("1b. Returns: shipping cost assigned by reason", function () {
    describe("approveReturn validation", function () {
      it("only the owner can approve a return", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await expect(ctx.escrow.connect(ctx.other).approveReturn(ref, Reason.WrongItem, U(5)))
          .to.be.revertedWithCustomError(ctx.escrow, "OwnableUnauthorizedAccount");
      });

      it("rejects reason None and WrongAddress (which has its own function)", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await expect(ctx.escrow.approveReturn(ref, Reason.None, 0))
          .to.be.revertedWithCustomError(ctx.escrow, "InvalidReturnReason");
        await expect(ctx.escrow.approveReturn(ref, Reason.WrongAddress, 0))
          .to.be.revertedWithCustomError(ctx.escrow, "InvalidReturnReason");
      });

      it("rejects a postage charge to the seller when the buyer changed their mind", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await expect(ctx.escrow.approveReturn(ref, Reason.ChangedMind, U(5)))
          .to.be.revertedWithCustomError(ctx.escrow, "InvalidAmount");
      });

      it("rejects seller postage above the product amount", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await expect(ctx.escrow.approveReturn(ref, Reason.Defective, U(101)))
          .to.be.revertedWithCustomError(ctx.escrow, "InvalidAmount");
      });

      it("requires an open dispute", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await placeOrder(ctx);
        await ship(ctx, ref);
        await expect(ctx.escrow.approveReturn(ref, Reason.WrongItem, 0))
          .to.be.revertedWithCustomError(ctx.escrow, "WrongStatus");
      });
    });

    describe("seller pays (defective, wrong item, not as described, damaged in transit)", function () {
      it("seller funds postage, buyer is reimbursed it and gets product + delivery back", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);

        await expect(ctx.escrow.approveReturn(ref, Reason.NotAsDescribed, U(8)))
          .to.emit(ctx.escrow, "ReturnApproved").withArgs(ref, Reason.NotAsDescribed, true, U(8), anyValue);

        await expect(ctx.escrow.connect(ctx.seller).fundReturnPostage(ref))
          .to.changeTokenBalances(ctx.token, [ctx.seller, ctx.escrow], [-U(8), U(8)]);

        await expect(shipReturn(ctx, ref))
          .to.emit(ctx.escrow, "ReturnPostageReimbursed").withArgs(ref, ctx.buyer.address, U(8));
        expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(8));

        await expect(ctx.escrow.connect(ctx.seller).confirmReturnReceived(ref))
          .to.emit(ctx.escrow, "ReturnCompleted").withArgs(ref, U(100), U(10), false);

        expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(118)); // 100 + 10 + 8 postage
        expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(0);
        expect(await ctx.escrow.balances(ctx.treasury.address)).to.equal(0); // no commission on refunds
        expect((await ctx.escrow.getOrder(ref)).status).to.equal(Status.Refunded);
        await expectSolvent(ctx);
      });

      it("Defective, WrongItem and DamagedInTransit: seller pays, delivery refunded", async function () {
        const ctx = await loadFixture(deployFixture);
        for (const reason of [Reason.Defective, Reason.WrongItem, Reason.DamagedInTransit]) {
          const ref = await shipAndDispute(ctx);
          await expect(ctx.escrow.approveReturn(ref, reason, 0)) // prepaid label: nothing to fund
            .to.emit(ctx.escrow, "ReturnApproved").withArgs(ref, reason, true, 0, anyValue);
          await shipReturn(ctx, ref);
          await expect(ctx.escrow.connect(ctx.seller).confirmReturnReceived(ref))
            .to.emit(ctx.escrow, "ReturnCompleted").withArgs(ref, U(100), U(10), false);
        }
        expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(330));
        await expectSolvent(ctx);
      });

      it("seller postage is taken from their earnings balance first", async function () {
        const ctx = await loadFixture(deployFixture);
        const paid = await placeOrder(ctx);
        await ship(ctx, paid);
        await ctx.escrow.connect(ctx.buyer).confirmReceipt(paid); // seller earnings = 108

        const ref = await shipAndDispute(ctx);
        await ctx.escrow.approveReturn(ref, Reason.WrongItem, U(8));
        await expect(ctx.escrow.connect(ctx.seller).fundReturnPostage(ref))
          .to.changeTokenBalance(ctx.token, ctx.seller, 0);
        expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U(100));
        await expectSolvent(ctx);
      });

      it("pulls only the shortfall from the seller's wallet", async function () {
        const ctx = await loadFixture(deployFixture);
        const paid = await placeOrder(ctx);
        await ship(ctx, paid);
        await ctx.escrow.connect(ctx.buyer).confirmReceipt(paid); // seller earnings = 108

        const ref = await shipAndDispute(ctx, { product: U(200) });
        await ctx.escrow.approveReturn(ref, Reason.WrongItem, U(150));
        const tx = ctx.escrow.connect(ctx.seller).fundReturnPostage(ref);
        await expect(tx).to.changeTokenBalance(ctx.token, ctx.seller, -U(42));
        await expect(tx).to.emit(ctx.escrow, "ReturnPostageFunded").withArgs(ref, U(150), U(108), anyValue);
        expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(0);
        await expectSolvent(ctx);
      });

      it("buyer cannot ship back before the seller funds postage", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await ctx.escrow.approveReturn(ref, Reason.NotAsDescribed, U(8));
        await expect(shipReturn(ctx, ref)).to.be.revertedWithCustomError(ctx.escrow, "ReturnNotFunded");
      });

      it("seller cannot fund twice or after the funding window", async function () {
        const ctx = await loadFixture(deployFixture);
        const a = await shipAndDispute(ctx);
        await ctx.escrow.approveReturn(a, Reason.NotAsDescribed, U(8));
        await ctx.escrow.connect(ctx.seller).fundReturnPostage(a);
        await expect(ctx.escrow.connect(ctx.seller).fundReturnPostage(a))
          .to.be.revertedWithCustomError(ctx.escrow, "AlreadyFunded");

        const b = await shipAndDispute(ctx);
        await ctx.escrow.approveReturn(b, Reason.NotAsDescribed, U(8));
        await time.increase(3 * DAY + 1);
        await expect(ctx.escrow.connect(ctx.seller).fundReturnPostage(b))
          .to.be.revertedWithCustomError(ctx.escrow, "TooLate");
      });

      it("unfunded postage: full refund and the buyer keeps the item", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await ctx.escrow.approveReturn(ref, Reason.Defective, U(8));

        await expect(ctx.escrow.connect(ctx.other).finalizeReturn(ref))
          .to.be.revertedWithCustomError(ctx.escrow, "TooEarly");
        await time.increase(3 * DAY + 1);
        await expect(ctx.escrow.connect(ctx.other).finalizeReturn(ref))
          .to.emit(ctx.escrow, "ReturnForfeited").withArgs(ref);

        expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(110));
        expect((await ctx.escrow.getOrder(ref)).status).to.equal(Status.Refunded);
        await expectSolvent(ctx);
      });

      it("buyer never ships back: seller is paid and gets the postage deposit back", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await ctx.escrow.approveReturn(ref, Reason.NotAsDescribed, U(8));
        await ctx.escrow.connect(ctx.seller).fundReturnPostage(ref);

        await time.increase(7 * DAY + 1);
        await expect(shipReturn(ctx, ref)).to.be.revertedWithCustomError(ctx.escrow, "TooLate");
        await expect(ctx.escrow.finalizeReturn(ref)).to.emit(ctx.escrow, "ReturnAbandoned").withArgs(ref);

        expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U(116)); // 110 - 2 commission + 8
        expect(await ctx.escrow.balances(ctx.treasury.address)).to.equal(U(2));
        expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(0);
        expect((await ctx.escrow.getOrder(ref)).status).to.equal(Status.Completed);
        await expectSolvent(ctx);
      });
    });

    describe("buyer pays: change of mind", function () {
      it("buyer pays postage, gets the product price back, seller keeps delivery", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);

        await expect(ctx.escrow.approveReturn(ref, Reason.ChangedMind, 0))
          .to.emit(ctx.escrow, "ReturnApproved").withArgs(ref, Reason.ChangedMind, false, 0, anyValue);
        expect((await ctx.escrow.getOrder(ref)).returnFunded).to.equal(true);

        await expect(shipReturn(ctx, ref)).to.not.emit(ctx.escrow, "ReturnPostageReimbursed");
        await ctx.escrow.connect(ctx.seller).confirmReturnReceived(ref);

        expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(100));
        expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U(10)); // delivery, no commission
        expect(await ctx.escrow.balances(ctx.treasury.address)).to.equal(0);
        expect((await ctx.escrow.getOrder(ref)).status).to.equal(Status.Completed);
        await expectSolvent(ctx);
      });
    });

    describe("buyer pays: wrong delivery address", function () {
      it("return cost is deducted from the refund and paid to the seller without commission", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);

        await expect(ctx.escrow.resolveWrongAddress(ref, U(15)))
          .to.emit(ctx.escrow, "WrongAddressResolved").withArgs(ref, U(15), U(85), U(25));

        expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(85)); // 100 - 15
        expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U(25)); // 10 delivery + 15 return
        expect(await ctx.escrow.balances(ctx.treasury.address)).to.equal(0);
        const o = await ctx.escrow.getOrder(ref);
        expect(o.status).to.equal(Status.Completed);
        expect(o.returnReason).to.equal(Reason.WrongAddress);
        await expectSolvent(ctx);
      });

      it("only the owner, only once, cost at most the product amount", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await expect(ctx.escrow.connect(ctx.other).resolveWrongAddress(ref, U(15)))
          .to.be.revertedWithCustomError(ctx.escrow, "OwnableUnauthorizedAccount");
        await expect(ctx.escrow.resolveWrongAddress(ref, U(101)))
          .to.be.revertedWithCustomError(ctx.escrow, "InvalidAmount");
        await ctx.escrow.resolveWrongAddress(ref, U(15));
        await expect(ctx.escrow.resolveWrongAddress(ref, U(15)))
          .to.be.revertedWithCustomError(ctx.escrow, "WrongStatus");
      });
    });

    describe("shared or unclear responsibility", function () {
      it("owner splits the refund with resolveDispute", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await ctx.escrow.resolveDispute(ref, U(50), U(5)); // half the product, half the delivery

        expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(55));
        expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U(54)); // 50 + 5 - 1 commission
        expect(await ctx.escrow.balances(ctx.treasury.address)).to.equal(U(1));
        await expectSolvent(ctx);
      });
    });

    describe("receiving the return", function () {
      it("seller silent past the domestic window: treated as received", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await ctx.escrow.approveReturn(ref, Reason.WrongItem, 0);
        await shipReturn(ctx, ref);

        await time.increase(13 * DAY);
        await expect(ctx.escrow.finalizeReturn(ref)).to.be.revertedWithCustomError(ctx.escrow, "TooEarly");
        await time.increase(DAY + 1);
        await expect(ctx.escrow.finalizeReturn(ref))
          .to.emit(ctx.escrow, "ReturnCompleted").withArgs(ref, U(100), U(10), true);
        expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(110));
        await expectSolvent(ctx);
      });

      it("international returns get 30 days, and the dispute deadline no longer forces a refund", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx, { international: true });
        await ctx.escrow.approveReturn(ref, Reason.WrongItem, 0);
        await shipReturn(ctx, ref);

        await time.increase(20 * DAY); // past the original 14-day dispute deadline
        await expect(ctx.escrow.resolveExpiredDispute(ref))
          .to.be.revertedWithCustomError(ctx.escrow, "WrongStatus");
        await expect(ctx.escrow.finalizeReturn(ref)).to.be.revertedWithCustomError(ctx.escrow, "TooEarly");

        await time.increase(10 * DAY + 1);
        await ctx.escrow.finalizeReturn(ref);
        expect((await ctx.escrow.getOrder(ref)).status).to.equal(Status.Refunded);
      });

      it("return shipment needs carrier, tracking and a valid date", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await ctx.escrow.approveReturn(ref, Reason.WrongItem, 0);
        const { shippedAt } = await ctx.escrow.getOrder(ref);

        await expect(
          ctx.escrow.connect(ctx.buyer).markReturnShipped(ref, RETURN_CARRIER, ZeroHash, ZeroHash, await time.latest())
        ).to.be.revertedWithCustomError(ctx.escrow, "InvalidShipment");
        await expect(shipReturn(ctx, ref, shippedAt - 1n))
          .to.be.revertedWithCustomError(ctx.escrow, "InvalidShipment");
        await expect(
          ctx.escrow.connect(ctx.other).markReturnShipped(ref, RETURN_CARRIER, RETURN_TRACKING, ZeroHash, await time.latest())
        ).to.be.revertedWithCustomError(ctx.escrow, "NotBuyer");
      });

      it("seller contests: back to the owner, a second return cannot be approved", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await ctx.escrow.approveReturn(ref, Reason.NotAsDescribed, U(8));
        await ctx.escrow.connect(ctx.seller).fundReturnPostage(ref);
        await shipReturn(ctx, ref);

        await expect(ctx.escrow.connect(ctx.seller).contestReturn(ref, ethers.id("box arrived empty")))
          .to.emit(ctx.escrow, "ReturnContested");
        expect((await ctx.escrow.getOrder(ref)).status).to.equal(Status.Disputed);

        await expect(ctx.escrow.approveReturn(ref, Reason.WrongItem, 0))
          .to.be.revertedWithCustomError(ctx.escrow, "ReturnAlreadyDecided");
        await expect(ctx.escrow.resolveWrongAddress(ref, 0))
          .to.be.revertedWithCustomError(ctx.escrow, "ReturnAlreadyDecided");

        await ctx.escrow.resolveDispute(ref, 0, 0); // owner sides with the seller
        expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U(108));
        expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(8)); // postage already spent
        await expectSolvent(ctx);
      });

      it("contested seller-paid return with no decision: full refund", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await ctx.escrow.approveReturn(ref, Reason.WrongItem, 0);
        await shipReturn(ctx, ref);
        await ctx.escrow.connect(ctx.seller).contestReturn(ref, ZeroHash);

        await time.increase(14 * DAY + 1);
        await expect(ctx.escrow.resolveExpiredDispute(ref))
          .to.emit(ctx.escrow, "DisputeResolved").withArgs(ref, U(100), U(10), true);
        expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(110));
        await expectSolvent(ctx);
      });

      it("contested change-of-mind return with no decision: seller still keeps delivery (L1)", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await ctx.escrow.approveReturn(ref, Reason.ChangedMind, 0);
        await shipReturn(ctx, ref);
        await ctx.escrow.connect(ctx.seller).contestReturn(ref, ZeroHash);

        await time.increase(14 * DAY + 1);
        await expect(ctx.escrow.resolveExpiredDispute(ref))
          .to.emit(ctx.escrow, "DisputeResolved").withArgs(ref, U(100), 0, true);
        expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(100));
        expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U(10));
        await expectSolvent(ctx);
      });

      it("only the seller confirms or contests", async function () {
        const ctx = await loadFixture(deployFixture);
        const ref = await shipAndDispute(ctx);
        await ctx.escrow.approveReturn(ref, Reason.WrongItem, 0);
        await shipReturn(ctx, ref);
        await expect(ctx.escrow.connect(ctx.buyer).confirmReturnReceived(ref))
          .to.be.revertedWithCustomError(ctx.escrow, "NotSeller");
        await expect(ctx.escrow.connect(ctx.buyer).contestReturn(ref, ZeroHash))
          .to.be.revertedWithCustomError(ctx.escrow, "NotSeller");
      });
    });
  });

  // 2. Delivery reduction sent straight to the buyer
  describe("2. Delivery reduction refunded directly to the buyer's wallet", function () {
    it("transfers the difference to the paying wallet in the same transaction", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);

      const tx = ctx.escrow.connect(ctx.seller).proposeDeliveryAdjustment(ref, U(4), ZeroHash);
      await expect(tx).to.changeTokenBalances(ctx.token, [ctx.buyer, ctx.escrow], [U(6), -U(6)]);
      await expect(tx).to.emit(ctx.escrow, "DeliveryReductionRefunded").withArgs(ref, ctx.buyer.address, U(6));

      expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(0); // nothing left to withdraw
      expect((await ctx.escrow.getOrder(ref)).deliveryAmount).to.equal(U(4));
      expect(await ctx.escrow.totalHeld()).to.equal(U(104));
      await expectSolvent(ctx);
    });

    it("works when delivery is reduced to zero", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await expect(ctx.escrow.connect(ctx.seller).proposeDeliveryAdjustment(ref, 0, ZeroHash))
        .to.changeTokenBalance(ctx.token, ctx.buyer, U(10));
      await expectSolvent(ctx);
    });

    it("the reduced order still settles correctly", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await ctx.escrow.connect(ctx.seller).proposeDeliveryAdjustment(ref, U(4), ZeroHash);
      await ship(ctx, ref);
      await ctx.escrow.connect(ctx.buyer).confirmReceipt(ref);
      expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U(102)); // 100 + 4 - 2
      await expectSolvent(ctx);
    });

    it("a higher delivery fee still needs the buyer's acceptance", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await ctx.escrow.connect(ctx.seller).proposeDeliveryAdjustment(ref, U(15), ZeroHash);
      expect((await ctx.escrow.getOrder(ref)).status).to.equal(Status.AdjustmentProposed);
      await expect(ctx.escrow.connect(ctx.buyer).acceptDeliveryAdjustment(ref))
        .to.changeTokenBalance(ctx.token, ctx.buyer, -U(5));
      await expectSolvent(ctx);
    });

    it("no delivery change after the shipping deadline, so a late seller cannot delay the refund (M2)", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await time.increase(7 * DAY + 1);
      await expect(ctx.escrow.connect(ctx.seller).proposeDeliveryAdjustment(ref, U(15), ZeroHash))
        .to.be.revertedWithCustomError(ctx.escrow, "TooLate");
      await ctx.escrow.connect(ctx.other).refundUnshipped(ref);
      expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(110));
    });
  });

  // 3. Dispute management
  describe("3. Dispute management", function () {
    it("only the owner (Safe) decides disputes", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await shipAndDispute(ctx);
      await expect(ctx.escrow.connect(ctx.other).resolveDispute(ref, 0, 0))
        .to.be.revertedWithCustomError(ctx.escrow, "OwnableUnauthorizedAccount");
      await expect(ctx.escrow.connect(ctx.other).extendDispute(ref))
        .to.be.revertedWithCustomError(ctx.escrow, "OwnableUnauthorizedAccount");
      await ctx.escrow.resolveDispute(ref, 0, 0);
    });

    it("ownership moves only with two steps, and cannot be renounced", async function () {
      const ctx = await loadFixture(deployFixture);
      await ctx.escrow.transferOwnership(ctx.newOwner.address);
      expect(await ctx.escrow.owner()).to.equal(ctx.owner.address); // not yet accepted
      await ctx.escrow.connect(ctx.newOwner).acceptOwnership();
      expect(await ctx.escrow.owner()).to.equal(ctx.newOwner.address);

      const ref = await shipAndDispute(ctx);
      await expect(ctx.escrow.resolveDispute(ref, 0, 0))
        .to.be.revertedWithCustomError(ctx.escrow, "OwnableUnauthorizedAccount");
      await ctx.escrow.connect(ctx.newOwner).resolveDispute(ref, 0, 0);

      await expect(ctx.escrow.connect(ctx.newOwner).renounceOwnership())
        .to.be.revertedWithCustomError(ctx.escrow, "RenounceDisabled");
    });

    it("buyer can withdraw their dispute: seller paid normally (M1)", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await shipAndDispute(ctx);
      await expect(ctx.escrow.connect(ctx.other).withdrawDispute(ref))
        .to.be.revertedWithCustomError(ctx.escrow, "NotBuyer");
      await expect(ctx.escrow.connect(ctx.buyer).withdrawDispute(ref))
        .to.emit(ctx.escrow, "DisputeWithdrawn").withArgs(ref);

      expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U(108));
      expect(await ctx.escrow.balances(ctx.treasury.address)).to.equal(U(2));
      expect((await ctx.escrow.getOrder(ref)).status).to.equal(Status.Completed);
      await expectSolvent(ctx);
    });

    it("buyer cannot withdraw a dispute once a return was approved", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await shipAndDispute(ctx);
      await ctx.escrow.approveReturn(ref, Reason.WrongItem, 0);
      await shipReturn(ctx, ref);
      await ctx.escrow.connect(ctx.seller).contestReturn(ref, ZeroHash);
      await expect(ctx.escrow.connect(ctx.buyer).withdrawDispute(ref))
        .to.be.revertedWithCustomError(ctx.escrow, "ReturnAlreadyDecided");
    });

    it("seller can concede: full refund to the buyer (M1)", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await shipAndDispute(ctx);
      await expect(ctx.escrow.connect(ctx.buyer).concedeDispute(ref))
        .to.be.revertedWithCustomError(ctx.escrow, "NotSeller");
      await expect(ctx.escrow.connect(ctx.seller).concedeDispute(ref))
        .to.emit(ctx.escrow, "DisputeConceded").withArgs(ref);
      expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(110));
      expect((await ctx.escrow.getOrder(ref)).status).to.equal(Status.Refunded);
      await expectSolvent(ctx);
    });

    it("no owner decision in time: full refund", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await shipAndDispute(ctx);
      await time.increase(14 * DAY + 1);
      await ctx.escrow.connect(ctx.other).resolveExpiredDispute(ref);
      expect(await ctx.escrow.refunds(ctx.buyer.address)).to.equal(U(110));
    });
  });

  // 4. Commission split
  describe("4. Commission split", function () {
    it("no referrer: PLEXUS keeps the whole 2%", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await ship(ctx, ref);
      await ctx.escrow.connect(ctx.buyer).confirmReceipt(ref);

      expect(await ctx.escrow.balances(ctx.treasury.address)).to.equal(U(2));
      expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U(108));
      expect(await ctx.escrow.rewards(ctx.buyer.address)).to.equal(0);
      await expectSolvent(ctx);
    });

    it("third-party referrer: 30% referrer, 20% buyer, 50% PLEXUS", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx, { referrer: ctx.referrer.address });
      await ship(ctx, ref);
      await ctx.escrow.connect(ctx.buyer).confirmReceipt(ref);

      expect(await ctx.escrow.rewards(ctx.referrer.address)).to.equal(U("0.6"));
      expect(await ctx.escrow.rewards(ctx.buyer.address)).to.equal(U("0.4"));
      expect(await ctx.escrow.balances(ctx.treasury.address)).to.equal(U(1));
      await expectSolvent(ctx);
    });

    it("referrer is the seller: 0% referrer, 20% buyer, 80% PLEXUS", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx, { referrer: ctx.seller.address });
      const excluded = await ctx.escrow.queryFilter(ctx.escrow.filters.SellerReferrerExcluded(ref));
      expect(excluded.length).to.equal(1);
      expect((await ctx.escrow.getOrder(ref)).referrer).to.equal(ZeroAddress);
      await ship(ctx, ref);
      await ctx.escrow.connect(ctx.buyer).confirmReceipt(ref);

      expect(await ctx.escrow.rewards(ctx.buyer.address)).to.equal(U("0.4"));
      expect(await ctx.escrow.rewards(ctx.seller.address)).to.equal(0);
      expect(await ctx.escrow.balances(ctx.treasury.address)).to.equal(U("1.6"));
      expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U(108));
    });

    it("the signed quote must carry the current fee (L4)", async function () {
      const ctx = await loadFixture(deployFixture);
      const wrong = await signQuote(ctx, { feeBps: 300 });
      await expect(ctx.escrow.connect(ctx.buyer).createOrder(wrong.q, wrong.sig))
        .to.be.revertedWithCustomError(ctx.escrow, "FeeMismatch");

      const old = await signQuote(ctx); // signed at 2%
      await ctx.escrow.proposeFeeConfig(300, 3000, 2000);
      await time.increase(48 * 60 * 60);
      await ctx.escrow.executeFeeConfig();
      await expect(ctx.escrow.connect(ctx.buyer).createOrder(old.q, old.sig))
        .to.be.revertedWithCustomError(ctx.escrow, "FeeMismatch");
    });
  });

  // 5. Withdrawals
  describe("5. Withdrawals", function () {
    it("buyer refunds are paid in full with no minimum", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx, { product: U(1), delivery: 0 });
      await ctx.escrow.connect(ctx.seller).cancelBySeller(ref);
      await expect(ctx.escrow.connect(ctx.buyer).withdrawRefund())
        .to.changeTokenBalance(ctx.token, ctx.buyer, U(1));
      await expect(ctx.escrow.connect(ctx.buyer).withdrawRefund())
        .to.be.revertedWithCustomError(ctx.escrow, "NothingToWithdraw");
      await expectSolvent(ctx);
    });

    it("seller earnings below $5 cannot be withdrawn", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx, { product: U(3), delivery: U(1) });
      await ship(ctx, ref);
      await ctx.escrow.connect(ctx.buyer).confirmReceipt(ref); // seller earnings 3.94
      expect(await ctx.escrow.balances(ctx.seller.address)).to.equal(U("3.94"));
      await expect(ctx.escrow.connect(ctx.seller).withdraw())
        .to.be.revertedWithCustomError(ctx.escrow, "BelowMinimum");
    });

    it("seller earnings of $5 or more go to the seller's own wallet", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await ship(ctx, ref);
      await ctx.escrow.connect(ctx.buyer).confirmReceipt(ref);
      await expect(ctx.escrow.connect(ctx.seller).withdraw())
        .to.changeTokenBalance(ctx.token, ctx.seller, U(108));
      await expectSolvent(ctx);
    });

    it("refunds and earnings are separate for someone who is both buyer and seller", async function () {
      const ctx = await loadFixture(deployFixture);
      // `other` is both a seller and a buyer
      const sale = await placeOrder(ctx, { seller: ctx.other, product: U(2), delivery: 0 });
      await ctx.escrow.connect(ctx.other).markShipped(sale, CARRIER, TRACKING, ZeroHash, await time.latest());
      await ctx.escrow.connect(ctx.buyer).confirmReceipt(sale); // other earns 1.96

      const purchase = await placeOrder(ctx, { buyer: ctx.other, product: U(2), delivery: 0 });
      await ctx.escrow.connect(ctx.seller).cancelBySeller(purchase); // other refunded 2

      await expect(ctx.escrow.connect(ctx.other).withdraw())
        .to.be.revertedWithCustomError(ctx.escrow, "BelowMinimum");
      await expect(ctx.escrow.connect(ctx.other).withdrawRefund())
        .to.changeTokenBalance(ctx.token, ctx.other, U(2));
      expect(await ctx.escrow.balances(ctx.other.address)).to.equal(U("1.96"));
    });

    it("the treasury has no minimum", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await ship(ctx, ref);
      await ctx.escrow.connect(ctx.buyer).confirmReceipt(ref); // treasury 2
      await expect(ctx.escrow.connect(ctx.treasury).withdraw())
        .to.changeTokenBalance(ctx.token, ctx.treasury, U(2));
    });

    it("rewards need verification and at least $5", async function () {
      const ctx = await loadFixture(deployFixture);
      const small = await placeOrder(ctx, { referrer: ctx.referrer.address });
      await ship(ctx, small);
      await ctx.escrow.connect(ctx.buyer).confirmReceipt(small); // cashback 0.4

      await expect(ctx.escrow.connect(ctx.buyer).withdrawRewards())
        .to.be.revertedWithCustomError(ctx.escrow, "NotVerified");
      await ctx.escrow.connect(ctx.operator).setVerified(ctx.buyer.address, true);
      await expect(ctx.escrow.connect(ctx.buyer).withdrawRewards())
        .to.be.revertedWithCustomError(ctx.escrow, "BelowMinimum");

      const big = await placeOrder(ctx, { referrer: ctx.referrer.address, product: U(1150) });
      await ship(ctx, big);
      await ctx.escrow.connect(ctx.buyer).confirmReceipt(big); // cashback 4.6 → total 5.0
      await expect(ctx.escrow.connect(ctx.buyer).withdrawRewards())
        .to.changeTokenBalance(ctx.token, ctx.buyer, U(5));
      await expectSolvent(ctx);
    });

    it("withdrawals keep working while new orders are paused", async function () {
      const ctx = await loadFixture(deployFixture);
      const ref = await placeOrder(ctx);
      await ctx.escrow.connect(ctx.seller).cancelBySeller(ref);
      await ctx.escrow.pause();
      await expect(ctx.escrow.connect(ctx.buyer).withdrawRefund())
        .to.changeTokenBalance(ctx.token, ctx.buyer, U(110));
    });
  });

  // 6. BNB Smart Chain token
  describe("6. Token", function () {
    it("uses only the token fixed at deployment", async function () {
      const ctx = await loadFixture(deployFixture);
      expect(await ctx.escrow.token()).to.equal(ctx.token.target);
    });

    it("tokens sent directly are not credited to the sender; rescue never touches owed funds", async function () {
      const ctx = await loadFixture(deployFixture);
      await placeOrder(ctx); // 110 held
      await ctx.token.connect(ctx.other).transfer(ctx.escrow.target, U(50));

      await expect(ctx.escrow.rescueExcess())
        .to.changeTokenBalances(ctx.token, [ctx.treasury, ctx.escrow], [U(50), -U(50)]);
      expect(await ctx.escrow.totalHeld()).to.equal(U(110));
      await expectSolvent(ctx);
      await expect(ctx.escrow.rescueExcess()).to.be.revertedWithCustomError(ctx.escrow, "NothingToWithdraw");
    });
  });
});
