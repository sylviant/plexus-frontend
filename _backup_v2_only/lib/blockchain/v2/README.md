# PLEXUS escrow V2: in-app wallet payment (task 2.1)

The app pays and manages orders on the V2 escrow contract through the user's own wallet (WalletConnect).
**The app never holds a private key.** It asks the wallet to sign, and the user approves in the wallet app.

## Files

| File | Role |
|---|---|
| `escrow_v2_abi.g.dart`, `escrow_v2_deployment.g.dart` | **Generated** from the compiled contract and the deployment. Never edit by hand. |
| `escrow_v2_config.dart` | Chain id, contract and token addresses, RPC, confirmations. Overridable with `--dart-define`. |
| `escrow_v2_models.dart` | `SignedQuote` (what the server signs) and `PayStep`. |
| `escrow_v2_calldata.dart` | Builds the call data for every contract call. Tested byte for byte against ethers. |
| `escrow_v2_service.dart` | The payment logic: checks, approval, order creation, confirmations, order actions. |
| `wallet_connect_service.dart` | Connects the wallet and sends it each request. |
| `web3_chain_reader.dart` | Reads balances, allowances and receipts. Read-only. |
| `escrow_api.dart` | Talks to the PLEXUS backend (quote, payment report). `DevQuoteApi` stands in until the backend has the endpoint. |
| `escrow_payment_flow.dart` | **The one call a screen makes:** `payOrder(orderId)`. |
| `escrow_v2_errors.dart` | Turns any failure into a message that is safe to show to a user. |

## What a payment screen does

```dart
final wallet  = WalletConnectService();                       // connect once: startPairing(), then wait for onConnected
final service = EscrowV2Service(config: const EscrowV2Config(), sender: wallet,
                                reader: Web3ChainReader(const EscrowV2Config()));
final flow    = EscrowPaymentFlow(service: service, api: HttpEscrowApi(baseUrl: ApiConfig.baseUrl, authToken: …));

try {
  final outcome = await flow.payOrder(orderId, onStep: (step) => setState(() => _step = step));
  // outcome.result.createOrderTx is the transaction; go to the "paid" screen
} on EscrowException catch (e) {
  showError(e.message);   // e.code is machine readable: USER_REJECTED, QUOTE_EXPIRED, INSUFFICIENT_USDT, …
}
```

Steps the user sees in the wallet: (1) approve USDT for exactly the order total (skipped if already approved),
(2) create the order. Order actions: `confirmReceipt`, `openDispute`, `acceptDeliveryAdjustment(extraAmount:)`,
`withdrawRefund`, `withdraw`, `withdrawRewards`, and for sellers `markShipped`, `cancelBySeller`,
`proposeDeliveryAdjustment`.

Checks made **before** the wallet is asked: wallet connected, the wallet is the buyer named in the quote, the quote is
not expired (with a 60 second margin), enough USDT. A quote that expires while the user is approving is caught before
the order is created.

## What the backend must provide (for the backend team, task 2.2)

`POST {api}/escrow/orders/{orderId}/quote`, login required. Answer (amounts are whole numbers in 18-decimal units):

```json
{ "orderRef": "0x…32 bytes", "buyer": "0x…", "seller": "0x…", "referrer": "0x0000…0000",
  "productAmount": "100000000000000000000", "deliveryAmount": "10000000000000000000",
  "feeBps": 200, "international": false, "validUntil": 1893456000, "signature": "0x…65 bytes" }
```

Signed with the operator key as EIP-712, domain `name "PlexusEscrow"`, `version "2"`, the chain id and the escrow
address; the struct fields in this order: orderRef, buyer, seller, referrer, productAmount, deliveryAmount, feeBps,
international, validUntil. `buyer` must be the wallet that will pay, `referrer` the buyer's registered referrer (or the
zero address), `feeBps` the contract's current fee. Optional: `POST …/payment` with `{"txHash":"0x…"}`.

## Testing before the backend exists

```
cd plexus-escrow
BUYER=<your wallet> SELLER=<another wallet> npm run quote:testnet      # prints the quote JSON
npm run mint:testnet                                                   # test USDT for the wallet (MINT_TO=…)
flutter run --dart-define=DEV_QUOTE_JSON='<the JSON>'                  # wire DevQuoteApi in the screen
```
The wallet also needs a little testnet BNB for gas.

## Testing in the browser (no phone needed)

On web the module also supports a wallet **extension** (MetaMask, Rabby…) through `window.ethereum`
(`injected_wallet.dart`; on phones it is an inert stand-in). A development test bench shows every step:

```
# 1. in plexus-escrow: a quote for the wallet you will pay with, and test USDT for it
$env:BUYER="<your wallet address>"; $env:SELLER="<any other address>"; npm run quote:testnet     # copy the JSON line
$env:MINT_TO="<your wallet address>"; npm run mint:testnet
# 2. in plexus-frontend: run the test bench in Chrome (the browser that has MetaMask)
flutter run -d chrome --web-port 8080 -t lib/main_wallet_test.dart
```
In the page: **Connect browser wallet** (MetaMask asks to connect and switches to BNB Testnet), paste the quote JSON,
**Pay this quote**. MetaMask asks twice: approve USDT, then create the order. The log shows both transaction links.
The buyer wallet needs a little testnet BNB for gas. The "Confirm receipt", "Open dispute" and "Withdraw refund" buttons
use the same quote's order number. The seller side (ship, cancel) needs a second wallet and is not on this page yet.

## Keeping the app in step with the contract

After any contract change or redeploy: `cd plexus-escrow && npx hardhat compile && npm run export:app`, then run the tests.

```
flutter test test/blockchain
```
The golden file `test/fixtures/escrow_v2_calldata.json` and the real signed quote `test/fixtures/dev_quote.json` come from
the contract tooling; the Dart tests fail if the app encodes anything differently.

## How the screens use it

`escrow_session.dart` keeps one wallet connection for the whole app (WalletConnect, or a browser wallet on web).
- `payment_screen.dart`: connects the wallet; a cart or single product first creates the order on the server
  (`POST /orders`, product ids and quantities only, with an `Idempotency-Key` so a retry finds the same order), then
  `payOrder(orderId)`. An order opened from a chat is paid directly. A delivery-fee change from the seller is accepted
  with `acceptDeliveryAdjustmentForOrder`, which approves only the difference.
- `order_detail_screen.dart`: "confirm receipt" is a wallet transaction (`confirmReceipt`); the order shows delivered
  only when it went through.
- **Order number on-chain:** `EscrowSession.orderRefFor(orderId)` = keccak256 of the order id's text. The backend must
  sign its quotes with this value as `orderRef`.

The old V1 files (`escrow_contract.dart`, `escrow_abi.dart`, `wallet_service.dart`) have been deleted.

**Needs the backend (Sylviant, tasks 2.2 and 2.4):** the quote endpoint above. Until it exists, paying from the app
fails with "server error" after the order is created (the order stays unpaid and is reused on retry). The server does
not yet store a delivery address for an order opened from a chat, and the order status after payment or confirmation
is updated only by the server's V2 listener.

## Known limits

- `walletconnect_flutter_v2` is deprecated by its maker in favour of Reown AppKit. It works today; a move to
  `reown_appkit` is a separate piece of work.
- Not yet tested with a real wallet on a phone. Everything else (call data, checks, rejections, timeouts, the real signed
  quote) is covered by `flutter test test/blockchain`.
