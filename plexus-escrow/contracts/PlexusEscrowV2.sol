// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title PLEXUS marketplace escrow: USDT (BEP-20) on BNB Smart Chain.
contract PlexusEscrowV2 is Ownable2Step, ReentrancyGuard, Pausable, EIP712 {
    using SafeERC20 for IERC20;

    // Constants

    uint256 public constant BPS = 10_000;
    uint16 public constant MAX_FEE_BPS = 1_000; // hard cap: 10%
    uint256 public constant FEE_TIMELOCK = 48 hours;

    uint256 public constant SHIP_WINDOW = 7 days; // seller must ship within this
    uint256 public constant RELEASE_WINDOW_DOMESTIC = 14 days; // after shipping
    uint256 public constant RELEASE_WINDOW_INTERNATIONAL = 30 days; // after shipping
    uint256 public constant ADJUSTMENT_WINDOW = 5 days; // buyer reply time
    uint256 public constant DISPUTE_RESOLUTION_WINDOW = 14 days; // owner decision time
    uint256 public constant DISPUTE_EXTENSION = 14 days; // one extra period the owner can add

    uint256 public constant RETURN_FUND_WINDOW = 3 days; // seller funds return postage
    uint256 public constant RETURN_SHIP_WINDOW = 7 days; // buyer ships the item back
    uint256 public constant RETURN_RECEIVE_WINDOW_DOMESTIC = 14 days; // seller confirms or contests
    uint256 public constant RETURN_RECEIVE_WINDOW_INTERNATIONAL = 30 days;

    bytes32 public constant QUOTE_TYPEHASH = keccak256(
        "Quote(bytes32 orderRef,address buyer,address seller,address referrer,uint256 productAmount,uint256 deliveryAmount,uint16 feeBps,bool international,uint256 validUntil)"
    );

    // Types

    enum Status {
        None,
        Paid,
        AdjustmentProposed,
        Shipped,
        Disputed,
        Completed,
        Refunded,
        ReturnApproved,
        ReturnShipped
    }

    enum ReturnReason {
        None,
        NotAsDescribed,
        WrongItem,
        DamagedInTransit,
        ChangedMind,
        Defective,
        WrongAddress
    }

    struct Quote {
        bytes32 orderRef; // server order number
        address buyer;
        address seller;
        address referrer; // address(0) if none
        uint256 productAmount; // 18 decimals
        uint256 deliveryAmount; // 18 decimals
        uint16 feeBps; // must equal the current fee
        bool international;
        uint256 validUntil; // unix timestamp
    }

    struct FeeConfig {
        uint16 feeBps; // 200 = 2%
        uint16 referrerBps; // referrer share
        uint16 cashbackBps; // buyer cashback share
    }

    struct Order {
        address buyer;
        address seller;
        address referrer;
        uint256 productAmount;
        uint256 deliveryAmount;
        uint256 proposedDelivery;
        uint256 returnCost; // return postage or wrong-address cost
        uint16 feeBps;
        uint16 referrerBps;
        uint16 cashbackBps;
        Status status;
        ReturnReason returnReason;
        bool international;
        bool adjustmentUsed;
        bool disputeExtended;
        bool returnFunded;
        uint64 paidAt;
        uint64 shipDeadline;
        uint64 shippedAt; // date declared by the seller
        uint64 releaseAt;
        uint64 adjustmentDeadline;
        uint64 disputeDeadline;
        uint64 returnDeadline; // current return stage
    }

    // Storage

    IERC20 public immutable token; // BSC-USD on mainnet, MockUSDT on testnet
    uint256 public immutable minWithdrawal; // earnings and rewards only

    address public operator; // server key
    address public treasury; // PLEXUS commission wallet

    FeeConfig public feeConfig;
    FeeConfig public pendingFeeConfig;
    uint64 public pendingFeeEta; // 0 = no pending change

    mapping(bytes32 => Order) private _orders;

    mapping(address => address) public referrerOf;
    mapping(address => bool) public referralLocked;

    mapping(address => uint256) public refunds; // buyer refunds, no minimum
    mapping(address => uint256) public balances; // seller earnings, PLEXUS share
    mapping(address => uint256) public rewards; // referral rewards and cashback
    mapping(address => bool) public verified; // identity check passed

    /// Everything the contract owes.
    uint256 public totalHeld;

    // Events

    event OrderCreated(
        bytes32 indexed orderRef,
        address indexed buyer,
        address indexed seller,
        uint256 productAmount,
        uint256 deliveryAmount,
        address referrer,
        uint16 feeBps
    );
    event DeliveryAdjustmentProposed(
        bytes32 indexed orderRef, uint256 oldDelivery, uint256 newDelivery, uint64 deadline, bytes32 reasonHash
    );
    event DeliveryAdjusted(bytes32 indexed orderRef, uint256 oldDelivery, uint256 newDelivery);
    event DeliveryAdjustmentDeclined(bytes32 indexed orderRef);
    event DeliveryReductionRefunded(bytes32 indexed orderRef, address indexed buyer, uint256 amount);
    event Shipped(
        bytes32 indexed orderRef,
        bytes32 carrierId,
        bytes32 trackingHash,
        bytes32 proofHash,
        uint64 shippedAt,
        uint64 releaseAt
    );
    event DisputeOpened(bytes32 indexed orderRef, bytes32 reasonHash, uint64 deadline);
    event DisputeExtended(bytes32 indexed orderRef, uint64 newDeadline);
    event DisputeResolved(bytes32 indexed orderRef, uint256 productRefund, uint256 deliveryRefund, bool expired);
    event DisputeWithdrawn(bytes32 indexed orderRef); // buyer closed it: seller paid
    event DisputeConceded(bytes32 indexed orderRef); // seller refunded in full
    event WrongAddressResolved(
        bytes32 indexed orderRef, uint256 returnCost, uint256 buyerRefund, uint256 sellerAmount
    );
    event ReturnApproved(
        bytes32 indexed orderRef, ReturnReason reason, bool sellerPaysPostage, uint256 returnCost, uint64 deadline
    );
    event ReturnPostageFunded(bytes32 indexed orderRef, uint256 amount, uint256 fromBalance, uint64 shipDeadline);
    event ReturnShipped(
        bytes32 indexed orderRef,
        bytes32 carrierId,
        bytes32 trackingHash,
        bytes32 proofHash,
        uint64 shippedAt,
        uint64 receiveDeadline
    );
    event ReturnPostageReimbursed(bytes32 indexed orderRef, address indexed buyer, uint256 amount);
    event ReturnContested(bytes32 indexed orderRef, bytes32 reasonHash, uint64 disputeDeadline);
    event ReturnCompleted(bytes32 indexed orderRef, uint256 productRefund, uint256 deliveryRefund, bool expired);
    event ReturnForfeited(bytes32 indexed orderRef); // postage not funded
    event ReturnAbandoned(bytes32 indexed orderRef); // buyer did not ship back
    event Settled(bytes32 indexed orderRef, uint256 sellerNet, uint256 commission, uint256 refundToBuyer);
    event ReferralRewardsCredited(
        bytes32 indexed orderRef, address indexed referrer, uint256 referrerReward, uint256 buyerCashback
    );
    event OrderRefunded(bytes32 indexed orderRef, uint256 amount);
    event ReferralLocked(address indexed user, address indexed referrer);
    event SellerReferrerExcluded(bytes32 indexed orderRef, address indexed seller);
    event Withdrawn(address indexed account, uint256 amount);
    event RefundWithdrawn(address indexed account, uint256 amount);
    event RewardsWithdrawn(address indexed account, uint256 amount);
    event VerifiedSet(address indexed account, bool verified);
    event OperatorChanged(address indexed oldOperator, address indexed newOperator);
    event TreasuryChanged(address indexed oldTreasury, address indexed newTreasury);
    event FeeConfigProposed(uint16 feeBps, uint16 referrerBps, uint16 cashbackBps, uint64 eta);
    event FeeConfigExecuted(uint16 feeBps, uint16 referrerBps, uint16 cashbackBps);
    event FeeConfigCancelled();
    event ExcessRescued(uint256 amount);

    // Errors

    error ZeroAddress();
    error InvalidFeeConfig();
    error NotBuyer();
    error NotSeller();
    error NotOperator();
    error InvalidSeller();
    error InvalidReferrer();
    error ReferrerMismatch();
    error InvalidAmount();
    error FeeMismatch();
    error QuoteExpired();
    error BadSignature();
    error OrderExists();
    error OrderNotFound();
    error WrongStatus();
    error TooEarly();
    error TooLate();
    error AdjustmentAlreadyUsed();
    error AlreadyExtended();
    error TransferMismatch();
    error NothingToWithdraw();
    error NotVerified();
    error BelowMinimum();
    error NoPendingFeeConfig();
    error RenounceDisabled();
    error InvalidShipment();
    error InvalidReturnReason();
    error ReturnAlreadyDecided();
    error ReturnNotFunded();
    error AlreadyFunded();

    // Modifiers

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    // Constructor

    constructor(
        IERC20 token_,
        address owner_,
        address operator_,
        address treasury_,
        uint16 feeBps_,
        uint16 referrerBps_,
        uint16 cashbackBps_,
        uint256 minWithdrawal_
    ) Ownable(owner_) EIP712("PlexusEscrow", "2") {
        if (address(token_) == address(0) || operator_ == address(0) || treasury_ == address(0)) {
            revert ZeroAddress();
        }
        FeeConfig memory c = FeeConfig(feeBps_, referrerBps_, cashbackBps_);
        _validateFeeConfig(c);

        token = token_;
        operator = operator_;
        treasury = treasury_;
        feeConfig = c;
        minWithdrawal = minWithdrawal_;
    }

    // Buyer: pay

    /// Buyer pays a server-signed quote.
    function createOrder(Quote calldata q, bytes calldata signature) external nonReentrant whenNotPaused {
        if (msg.sender != q.buyer) revert NotBuyer();
        if (block.timestamp > q.validUntil) revert QuoteExpired();
        if (_orders[q.orderRef].status != Status.None) revert OrderExists();
        if (q.seller == address(0) || q.seller == q.buyer) revert InvalidSeller();
        if (q.productAmount == 0) revert InvalidAmount();
        if (q.feeBps != feeConfig.feeBps) revert FeeMismatch();
        if (ECDSA.recover(quoteDigest(q), signature) != operator) revert BadSignature();

        address referrer = _lockReferrer(q.buyer, q.referrer);
        _storeOrder(q, referrer);
        _pull(q.buyer, q.productAmount + q.deliveryAmount);
    }

    /// EIP-712 digest of a quote.
    function quoteDigest(Quote calldata q) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    QUOTE_TYPEHASH,
                    q.orderRef,
                    q.buyer,
                    q.seller,
                    q.referrer,
                    q.productAmount,
                    q.deliveryAmount,
                    q.feeBps,
                    q.international,
                    q.validUntil
                )
            )
        );
    }

    // Delivery fee adjustment

    /// Seller changes delivery once before shipping; a lower fee goes straight to the buyer.
    function proposeDeliveryAdjustment(bytes32 orderRef, uint256 newDelivery, bytes32 reasonHash)
        external
        nonReentrant
    {
        Order storage o = _order(orderRef);
        if (msg.sender != o.seller) revert NotSeller();
        if (o.status != Status.Paid) revert WrongStatus();
        if (block.timestamp >= o.shipDeadline) revert TooLate(); // cannot delay refundUnshipped
        if (o.adjustmentUsed) revert AdjustmentAlreadyUsed();
        if (newDelivery == o.deliveryAmount) revert InvalidAmount();

        o.adjustmentUsed = true;
        uint256 oldDelivery = o.deliveryAmount;

        if (newDelivery < oldDelivery) {
            uint256 diff = oldDelivery - newDelivery;
            o.deliveryAmount = newDelivery;
            totalHeld -= diff;
            emit DeliveryAdjusted(orderRef, oldDelivery, newDelivery);
            emit DeliveryReductionRefunded(orderRef, o.buyer, diff);
            token.safeTransfer(o.buyer, diff); // paying wallet
        } else {
            o.proposedDelivery = newDelivery;
            o.adjustmentDeadline = uint64(block.timestamp + ADJUSTMENT_WINDOW);
            o.status = Status.AdjustmentProposed;
            emit DeliveryAdjustmentProposed(orderRef, oldDelivery, newDelivery, o.adjustmentDeadline, reasonHash);
        }
    }

    /// Buyer accepts a higher delivery fee and pays the difference.
    function acceptDeliveryAdjustment(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (msg.sender != o.buyer) revert NotBuyer();
        if (o.status != Status.AdjustmentProposed) revert WrongStatus();
        if (block.timestamp >= o.adjustmentDeadline) revert TooLate();

        uint256 oldDelivery = o.deliveryAmount;
        uint256 diff = o.proposedDelivery - oldDelivery;

        o.deliveryAmount = o.proposedDelivery;
        o.proposedDelivery = 0;
        o.status = Status.Paid;
        o.shipDeadline = uint64(block.timestamp + SHIP_WINDOW); // fresh shipping window

        emit DeliveryAdjusted(orderRef, oldDelivery, o.deliveryAmount);
        _pull(o.buyer, diff);
    }

    /// Buyer declines a higher delivery fee: full refund.
    function declineDeliveryAdjustment(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (msg.sender != o.buyer) revert NotBuyer();
        if (o.status != Status.AdjustmentProposed) revert WrongStatus();
        emit DeliveryAdjustmentDeclined(orderRef);
        _refundAll(orderRef, o);
    }

    /// Unanswered proposal: full refund.
    function expireDeliveryAdjustment(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (o.status != Status.AdjustmentProposed) revert WrongStatus();
        if (block.timestamp < o.adjustmentDeadline) revert TooEarly();
        _refundAll(orderRef, o);
    }

    // Before shipping

    /// Seller cancels before shipping: full refund.
    function cancelBySeller(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (msg.sender != o.seller) revert NotSeller();
        if (o.status != Status.Paid && o.status != Status.AdjustmentProposed) revert WrongStatus();
        _refundAll(orderRef, o);
    }

    /// Not shipped in time: full refund.
    function refundUnshipped(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (o.status != Status.Paid) revert WrongStatus();
        if (block.timestamp < o.shipDeadline) revert TooEarly();
        _refundAll(orderRef, o);
    }

    // Shipping & release

    /// Seller records carrier, tracking hash, optional proof and shipping date.
    function markShipped(
        bytes32 orderRef,
        bytes32 carrierId,
        bytes32 trackingHash,
        bytes32 proofHash,
        uint64 shippedAt
    ) external nonReentrant {
        Order storage o = _order(orderRef);
        if (msg.sender != o.seller) revert NotSeller();
        if (o.status != Status.Paid) revert WrongStatus(); // blocked while an adjustment is open
        if (block.timestamp >= o.shipDeadline) revert TooLate();
        _checkShipment(carrierId, trackingHash, shippedAt, o.paidAt);

        o.status = Status.Shipped;
        o.shippedAt = shippedAt;
        uint256 window = o.international ? RELEASE_WINDOW_INTERNATIONAL : RELEASE_WINDOW_DOMESTIC;
        o.releaseAt = uint64(block.timestamp + window);
        emit Shipped(orderRef, carrierId, trackingHash, proofHash, shippedAt, o.releaseAt);
    }

    /// Buyer confirms receipt: seller is paid.
    function confirmReceipt(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (msg.sender != o.buyer) revert NotBuyer();
        if (o.status != Status.Shipped) revert WrongStatus();
        _settle(orderRef, o, 0, 0);
    }

    /// Release window passed without a dispute: seller is paid.
    function release(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (o.status != Status.Shipped) revert WrongStatus();
        if (block.timestamp < o.releaseAt) revert TooEarly();
        _settle(orderRef, o, 0, 0);
    }

    // Disputes

    /// Buyer disputes before release.
    function openDispute(bytes32 orderRef, bytes32 reasonHash) external nonReentrant {
        Order storage o = _order(orderRef);
        if (msg.sender != o.buyer) revert NotBuyer();
        if (o.status != Status.Shipped) revert WrongStatus();
        if (block.timestamp >= o.releaseAt) revert TooLate();

        o.status = Status.Disputed;
        o.disputeDeadline = uint64(block.timestamp + DISPUTE_RESOLUTION_WINDOW);
        emit DisputeOpened(orderRef, reasonHash, o.disputeDeadline);
    }

    /// Buyer closes the dispute: seller is paid.
    function withdrawDispute(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (msg.sender != o.buyer) revert NotBuyer();
        if (o.status != Status.Disputed) revert WrongStatus();
        if (o.returnReason != ReturnReason.None) revert ReturnAlreadyDecided();
        emit DisputeWithdrawn(orderRef);
        _settle(orderRef, o, 0, 0);
    }

    /// Seller concedes: full refund.
    function concedeDispute(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (msg.sender != o.seller) revert NotSeller();
        if (o.status != Status.Disputed) revert WrongStatus();
        emit DisputeConceded(orderRef);
        _settle(orderRef, o, o.productAmount, o.deliveryAmount);
    }

    /// Owner extends the dispute once.
    function extendDispute(bytes32 orderRef) external onlyOwner {
        Order storage o = _order(orderRef);
        if (o.status != Status.Disputed) revert WrongStatus();
        if (block.timestamp >= o.disputeDeadline) revert TooLate();
        if (o.disputeExtended) revert AlreadyExtended();

        o.disputeExtended = true;
        o.disputeDeadline += uint64(DISPUTE_EXTENSION);
        emit DisputeExtended(orderRef, o.disputeDeadline);
    }

    /// Owner decides the dispute with any split.
    function resolveDispute(bytes32 orderRef, uint256 productRefund, uint256 deliveryRefund)
        external
        onlyOwner
        nonReentrant
    {
        Order storage o = _order(orderRef);
        if (o.status != Status.Disputed) revert WrongStatus();
        if (block.timestamp >= o.disputeDeadline) revert TooLate();
        if (productRefund > o.productAmount || deliveryRefund > o.deliveryAmount) revert InvalidAmount();

        emit DisputeResolved(orderRef, productRefund, deliveryRefund, false);
        _settle(orderRef, o, productRefund, deliveryRefund);
    }

    /// No decision in time: full refund, or the approved return's outcome.
    function resolveExpiredDispute(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (o.status != Status.Disputed) revert WrongStatus();
        if (block.timestamp < o.disputeDeadline) revert TooEarly();

        uint256 deliveryRefund = _sellerPaysReturn(o.returnReason) ? o.deliveryAmount : 0;
        emit DisputeResolved(orderRef, o.productAmount, deliveryRefund, true);
        _settle(orderRef, o, o.productAmount, deliveryRefund);
    }

    // Returns

    /// Owner approves a return; the reason decides who pays postage.
    function approveReturn(bytes32 orderRef, ReturnReason reason, uint256 returnShippingCost)
        external
        onlyOwner
        nonReentrant
    {
        Order storage o = _order(orderRef);
        if (o.status != Status.Disputed) revert WrongStatus();
        if (block.timestamp >= o.disputeDeadline) revert TooLate();
        if (o.returnReason != ReturnReason.None) revert ReturnAlreadyDecided();
        if (reason == ReturnReason.None || reason == ReturnReason.WrongAddress) revert InvalidReturnReason();

        bool sellerPays = _sellerPaysReturn(reason);
        if (sellerPays ? returnShippingCost > o.productAmount : returnShippingCost != 0) revert InvalidAmount();

        o.returnReason = reason;
        o.returnCost = returnShippingCost;
        o.status = Status.ReturnApproved;
        if (returnShippingCost == 0) {
            o.returnFunded = true; // nothing to fund
            o.returnDeadline = uint64(block.timestamp + RETURN_SHIP_WINDOW);
        } else {
            o.returnDeadline = uint64(block.timestamp + RETURN_FUND_WINDOW);
        }
        emit ReturnApproved(orderRef, reason, sellerPays, returnShippingCost, o.returnDeadline);
    }

    /// Wrong address: return cost deducted from the buyer's refund, paid to the seller.
    function resolveWrongAddress(bytes32 orderRef, uint256 returnCost) external onlyOwner nonReentrant {
        Order storage o = _order(orderRef);
        if (o.status != Status.Disputed) revert WrongStatus();
        if (block.timestamp >= o.disputeDeadline) revert TooLate();
        if (o.returnReason != ReturnReason.None) revert ReturnAlreadyDecided();
        if (returnCost > o.productAmount) revert InvalidAmount();

        uint256 buyerRefund = o.productAmount - returnCost;
        uint256 sellerAmount = o.deliveryAmount + returnCost;

        o.returnReason = ReturnReason.WrongAddress;
        o.returnCost = returnCost;
        o.status = sellerAmount == 0 ? Status.Refunded : Status.Completed;

        if (buyerRefund > 0) refunds[o.buyer] += buyerRefund;
        if (sellerAmount > 0) balances[o.seller] += sellerAmount;

        emit WrongAddressResolved(orderRef, returnCost, buyerRefund, sellerAmount);
        emit Settled(orderRef, sellerAmount, 0, buyerRefund);
    }

    /// Seller deposits return postage (earnings first, then wallet).
    function fundReturnPostage(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (msg.sender != o.seller) revert NotSeller();
        if (o.status != Status.ReturnApproved) revert WrongStatus();
        if (o.returnFunded) revert AlreadyFunded();
        if (block.timestamp >= o.returnDeadline) revert TooLate();

        uint256 cost = o.returnCost;
        uint256 available = balances[msg.sender];
        uint256 fromBalance = available < cost ? available : cost;
        balances[msg.sender] = available - fromBalance; // earmarked for this return

        o.returnFunded = true;
        o.returnDeadline = uint64(block.timestamp + RETURN_SHIP_WINDOW);
        emit ReturnPostageFunded(orderRef, cost, fromBalance, o.returnDeadline);
        _pull(msg.sender, cost - fromBalance);
    }

    /// Buyer records the return shipment.
    function markReturnShipped(
        bytes32 orderRef,
        bytes32 carrierId,
        bytes32 trackingHash,
        bytes32 proofHash,
        uint64 shippedAt
    ) external nonReentrant {
        Order storage o = _order(orderRef);
        if (msg.sender != o.buyer) revert NotBuyer();
        if (o.status != Status.ReturnApproved) revert WrongStatus();
        if (!o.returnFunded) revert ReturnNotFunded();
        if (block.timestamp >= o.returnDeadline) revert TooLate();
        _checkShipment(carrierId, trackingHash, shippedAt, o.shippedAt);

        o.status = Status.ReturnShipped;
        uint256 window = o.international ? RETURN_RECEIVE_WINDOW_INTERNATIONAL : RETURN_RECEIVE_WINDOW_DOMESTIC;
        o.returnDeadline = uint64(block.timestamp + window);

        uint256 postage = o.returnCost;
        if (postage > 0) {
            refunds[o.buyer] += postage;
            emit ReturnPostageReimbursed(orderRef, o.buyer, postage);
        }
        emit ReturnShipped(orderRef, carrierId, trackingHash, proofHash, shippedAt, o.returnDeadline);
    }

    /// Seller confirms the return: buyer refunded by reason.
    function confirmReturnReceived(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (msg.sender != o.seller) revert NotSeller();
        if (o.status != Status.ReturnShipped) revert WrongStatus();
        _settleReturn(orderRef, o, false);
    }

    /// Seller contests the return: back to the owner.
    function contestReturn(bytes32 orderRef, bytes32 reasonHash) external nonReentrant {
        Order storage o = _order(orderRef);
        if (msg.sender != o.seller) revert NotSeller();
        if (o.status != Status.ReturnShipped) revert WrongStatus();
        if (block.timestamp >= o.returnDeadline) revert TooLate();

        o.status = Status.Disputed;
        o.disputeDeadline = uint64(block.timestamp + DISPUTE_RESOLUTION_WINDOW);
        o.disputeExtended = false;
        emit ReturnContested(orderRef, reasonHash, o.disputeDeadline);
    }

    /// Default outcome when a return stage times out.
    function finalizeReturn(bytes32 orderRef) external nonReentrant {
        Order storage o = _order(orderRef);
        if (o.status != Status.ReturnApproved && o.status != Status.ReturnShipped) revert WrongStatus();
        if (block.timestamp < o.returnDeadline) revert TooEarly();

        if (o.status == Status.ReturnShipped) {
            _settleReturn(orderRef, o, true);
        } else if (!o.returnFunded) {
            emit ReturnForfeited(orderRef);
            _refundAll(orderRef, o);
        } else {
            if (o.returnCost > 0) balances[o.seller] += o.returnCost;
            emit ReturnAbandoned(orderRef);
            _settle(orderRef, o, 0, 0);
        }
    }

    // Withdrawals

    /// Withdraw buyer refunds in full, no minimum.
    function withdrawRefund() external nonReentrant {
        uint256 amount = refunds[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        refunds[msg.sender] = 0;
        totalHeld -= amount;
        token.safeTransfer(msg.sender, amount);
        emit RefundWithdrawn(msg.sender, amount);
    }

    /// Withdraw seller earnings ($5 minimum, treasury exempt).
    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        if (amount < minWithdrawal && msg.sender != treasury) revert BelowMinimum();
        balances[msg.sender] = 0;
        totalHeld -= amount;
        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    /// Withdraw rewards (identity check, $5 minimum).
    function withdrawRewards() external nonReentrant {
        if (!verified[msg.sender]) revert NotVerified();
        uint256 amount = rewards[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        if (amount < minWithdrawal) revert BelowMinimum();
        rewards[msg.sender] = 0;
        totalHeld -= amount;
        token.safeTransfer(msg.sender, amount);
        emit RewardsWithdrawn(msg.sender, amount);
    }

    // Operator

    /// Operator records an identity check.
    function setVerified(address account, bool isVerified) external onlyOperator {
        verified[account] = isVerified;
        emit VerifiedSet(account, isVerified);
    }

    // Owner

    function setOperator(address newOperator) external onlyOwner {
        if (newOperator == address(0)) revert ZeroAddress();
        emit OperatorChanged(operator, newOperator);
        operator = newOperator;
    }

    function setTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddress();
        emit TreasuryChanged(treasury, newTreasury);
        treasury = newTreasury;
    }

    /// Stops new orders only.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// Propose a fee change (48h timelock, new orders only).
    function proposeFeeConfig(uint16 feeBps_, uint16 referrerBps_, uint16 cashbackBps_) external onlyOwner {
        FeeConfig memory c = FeeConfig(feeBps_, referrerBps_, cashbackBps_);
        _validateFeeConfig(c);
        pendingFeeConfig = c;
        pendingFeeEta = uint64(block.timestamp + FEE_TIMELOCK);
        emit FeeConfigProposed(feeBps_, referrerBps_, cashbackBps_, pendingFeeEta);
    }

    /// Anyone applies the fee change after the timelock.
    function executeFeeConfig() external {
        if (pendingFeeEta == 0) revert NoPendingFeeConfig();
        if (block.timestamp < pendingFeeEta) revert TooEarly();
        feeConfig = pendingFeeConfig;
        delete pendingFeeConfig;
        pendingFeeEta = 0;
        emit FeeConfigExecuted(feeConfig.feeBps, feeConfig.referrerBps, feeConfig.cashbackBps);
    }

    function cancelFeeConfig() external onlyOwner {
        if (pendingFeeEta == 0) revert NoPendingFeeConfig();
        delete pendingFeeConfig;
        pendingFeeEta = 0;
        emit FeeConfigCancelled();
    }

    /// Sends tokens beyond totalHeld to the treasury.
    function rescueExcess() external onlyOwner nonReentrant {
        uint256 excess = token.balanceOf(address(this)) - totalHeld;
        if (excess == 0) revert NothingToWithdraw();
        token.safeTransfer(treasury, excess);
        emit ExcessRescued(excess);
    }

    /// Disabled: disputes need an owner.
    function renounceOwnership() public pure override {
        revert RenounceDisabled();
    }

    // Views

    function getOrder(bytes32 orderRef) external view returns (Order memory) {
        return _orders[orderRef];
    }

    // Internals

    function _order(bytes32 orderRef) private view returns (Order storage o) {
        o = _orders[orderRef];
        if (o.status == Status.None) revert OrderNotFound();
    }

    /// Carrier and tracking required; date between notBefore and now.
    function _checkShipment(bytes32 carrierId, bytes32 trackingHash, uint64 shippedAt, uint64 notBefore)
        private
        view
    {
        if (carrierId == bytes32(0) || trackingHash == bytes32(0)) revert InvalidShipment();
        if (shippedAt < notBefore || shippedAt > block.timestamp) revert InvalidShipment();
    }

    /// Seller is responsible unless ChangedMind or WrongAddress.
    function _sellerPaysReturn(ReturnReason reason) private pure returns (bool) {
        return reason != ReturnReason.ChangedMind && reason != ReturnReason.WrongAddress;
    }

    function _settleReturn(bytes32 orderRef, Order storage o, bool expired) private {
        uint256 deliveryRefund = _sellerPaysReturn(o.returnReason) ? o.deliveryAmount : 0;
        emit ReturnCompleted(orderRef, o.productAmount, deliveryRefund, expired);
        _settle(orderRef, o, o.productAmount, deliveryRefund);
    }

    /// Locks the referrer on the buyer's first order.
    function _lockReferrer(address buyer, address quoted) private returns (address) {
        if (!referralLocked[buyer]) {
            if (quoted == buyer) revert InvalidReferrer();
            referralLocked[buyer] = true;
            referrerOf[buyer] = quoted;
            emit ReferralLocked(buyer, quoted);
            return quoted;
        }
        if (quoted != referrerOf[buyer]) revert ReferrerMismatch();
        return quoted;
    }

    /// Stores the order with its fee and referral snapshot.
    function _storeOrder(Quote calldata q, address referrer) private {
        FeeConfig memory c = feeConfig;
        bool referred = referrer != address(0);
        bool sellerIsReferrer = referred && referrer == q.seller;
        address orderReferrer = sellerIsReferrer ? address(0) : referrer;

        Order storage o = _orders[q.orderRef];
        o.buyer = q.buyer;
        o.seller = q.seller;
        o.referrer = orderReferrer;
        o.productAmount = q.productAmount;
        o.deliveryAmount = q.deliveryAmount;
        o.feeBps = c.feeBps;
        o.referrerBps = orderReferrer != address(0) ? c.referrerBps : 0;
        o.cashbackBps = referred ? c.cashbackBps : 0;
        o.status = Status.Paid;
        o.international = q.international;
        o.paidAt = uint64(block.timestamp);
        o.shipDeadline = uint64(block.timestamp + SHIP_WINDOW);

        if (sellerIsReferrer) emit SellerReferrerExcluded(q.orderRef, referrer);
        emit OrderCreated(
            q.orderRef, q.buyer, q.seller, q.productAmount, q.deliveryAmount, orderReferrer, c.feeBps
        );
    }

    /// Pulls exactly `amount`; rejects fee-on-transfer tokens.
    function _pull(address from, uint256 amount) private {
        if (amount == 0) return;
        uint256 before = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        if (token.balanceOf(address(this)) - before != amount) revert TransferMismatch();
        totalHeld += amount;
    }

    function _refundAll(bytes32 orderRef, Order storage o) private {
        uint256 amount = o.productAmount + o.deliveryAmount;
        o.status = Status.Refunded;
        refunds[o.buyer] += amount;
        emit OrderRefunded(orderRef, amount);
    }

    /// Splits an order into buyer refund, seller payout, commission and rewards.
    function _settle(bytes32 orderRef, Order storage o, uint256 productRefund, uint256 deliveryRefund) private {
        uint256 sellerProduct = o.productAmount - productRefund;
        uint256 toSeller = sellerProduct + (o.deliveryAmount - deliveryRefund);

        o.status = toSeller == 0 ? Status.Refunded : Status.Completed;

        if (productRefund + deliveryRefund > 0) {
            refunds[o.buyer] += productRefund + deliveryRefund;
        }

        uint256 commission = (sellerProduct * o.feeBps) / BPS;
        uint256 plexusShare;
        {
            uint256 referrerReward = (commission * o.referrerBps) / BPS; // 0 unless a third-party referrer
            uint256 cashback = (commission * o.cashbackBps) / BPS; // 0 unless the buyer was referred
            plexusShare = commission - referrerReward - cashback; // rounding dust stays with PLEXUS

            if (referrerReward > 0) rewards[o.referrer] += referrerReward;
            if (cashback > 0) rewards[o.buyer] += cashback;
            if (referrerReward + cashback > 0) {
                emit ReferralRewardsCredited(orderRef, o.referrer, referrerReward, cashback);
            }
        }

        if (plexusShare > 0) balances[treasury] += plexusShare;
        if (toSeller > 0) balances[o.seller] += toSeller - commission;

        emit Settled(orderRef, toSeller - commission, commission, productRefund + deliveryRefund);
    }

    function _validateFeeConfig(FeeConfig memory c) private pure {
        if (c.feeBps > MAX_FEE_BPS) revert InvalidFeeConfig();
        if (uint256(c.referrerBps) + c.cashbackBps > BPS) revert InvalidFeeConfig();
    }
}
