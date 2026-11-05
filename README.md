# PLEXUS Frontend (Flutter)

Mobile and web client of the PLEXUS marketplace.
Buyers and sellers browse products, chat, order and pay in BNB through an escrow smart contract on BNB Smart Chain.

- Framework: Flutter (Material 3), one codebase for Android, iOS and Web
- Web deployment: Vercel (served from `build/web`)
- Backend: see `README-backend.md` (base URL in `lib/core/api_config.dart`)

> This README was written from the `lib/` folder only.
> `pubspec.yaml`, `assets/`, `android/`, `ios/`, `web/`, `vercel.json` and the `.arb` localisation sources were **not** available. Anything marked **(to confirm)** comes from that gap.

---

## 1. Tech stack

Packages are inferred from the imports in `lib/` (check versions in `pubspec.yaml`).

| Area | Package |
|---|---|
| State | `provider` (`ChangeNotifier`) |
| Navigation | `go_router` (`StatefulShellRoute` for the bottom bar) |
| HTTP | `http` |
| Real-time | `socket_io_client` |
| Auth | `firebase_auth`, `google_sign_in`, `shared_preferences` |
| Push | `firebase_core`, `firebase_messaging`, `flutter_local_notifications` |
| Blockchain | `walletconnect_flutter_v2`, `web3dart`, `url_launcher`, `qr_flutter` |
| UI | `native_glass_navbar` (iOS 26 style bottom bar), `flutter_staggered_grid_view`, `dash_chat_2` |
| Media / location | `image_picker`, `geolocator`, `geocoding`, `http_parser`, `path` |
| i18n | `flutter_localizations`, `intl` |

---

## 2. Getting started

```bash
flutter pub get
flutter run                      # mobile, uses the production backend by default
flutter run -d chrome            # web
flutter build web                # output in build/web
flutter build apk --release
```

Requirements:
- A Firebase project with the config files for each platform (`google-services.json`, `GoogleService-Info.plist`). The web config is inlined in `main.dart`, and `lib/firebase_options.dart` exists too.
- `assets/logo/logo.png`, `assets/images/pub2.png` and the wallet icons `assets/wallets/{metamask,trust,binance,coinbase,rainbow,safepal,okx,cryptocom}.png` must be declared in `pubspec.yaml`. Missing wallet icons fall back to a generic icon.
- Android/iOS: to detect installed wallets with `canLaunchUrl`, declare the wallet URL schemes (`metamask`, `trust`, `bnc`, `cbwallet`, `rainbow`, `safepal`, `okex`, `cryptowallet`) in `AndroidManifest.xml` (`<queries>`) and `LSApplicationQueriesSchemes` in `Info.plist` **(to confirm they are present)**.

To point the app at a local backend, change `serverUrl` in `lib/core/api_config.dart`.

---

## 3. Project structure

```
lib/
  main.dart                    app bootstrap, providers, theme, locale
  firebase_options.dart
  core/
    api_config.dart            backend URL, image URL repair, network error text
    router.dart                all routes + auth redirect
    constants/countries.dart   country codes for delivery country
    models/                    cart_item, ai_product, user_type
    providers/                 auth, user, cart, favorite, category, notification, socket
    services/                  ai_chat_service, notification_service
  blockchain/
    wallet_service.dart        WalletConnect v2 session + wallet deep links
    escrow_contract.dart       web3dart wrapper of the escrow contract
    escrow_abi.dart            partial ABI (JSON string)
  l10n/                        10 languages + l10n.dart helper
  presentation/
    scaffold_with_nav_bar.dart bottom navigation shell
    screens/                   all screens (see section 6)
    widgets/                   product cards, category list
```

Files to clean up: `lib/Nouveau dossier/` and `lib/Nouveau dossier.zip` (old copies of home, product detail, add product, product card), `presentation/yooy.dart` (empty), `core/models/product_card_widget.dart` (empty), and `presentation/widgets/product_card.dart` vs `product_card_widget.dart` (two similar widgets).

---

## 4. App bootstrap and state

`main.dart`:
1. Initialises date formatting and the language (`L10n.initFromDevice()`).
2. Initialises Firebase (web uses inline options) and local notifications.
3. Starts `MultiProvider` with the providers below.
4. After first frame, if logged in: connects the socket, loads notifications and favorites, registers the FCM token (mobile only).

| Provider | Role |
|---|---|
| `UserProvider` | current user type (`client` or `seller`), decides profile vs seller hub |
| `AuthProvider` | login, signup, Google sign-in (popup on web, `google_sign_in` on mobile), token and user persisted in `SharedPreferences` (`auth_token`, `user_data`), `isAuthenticated = token != null`, FCM token update |
| `CartProvider` | cart items, `rawPrice`, promo percentage, `discountAmount`, `totalPrice` |
| `SocketProvider` | Socket.IO connection, chat messages, incoming notifications |
| `NotificationProvider` | notification list, mark as read |
| `FavoriteProvider` | favorites fetch and toggle |
| `CategoryProvider` | categories fetch |

Theme: light only, primary colour `0xFF1A237E`, secondary `0xFF4A6CF7`, rounded cards and buttons. Some screens (for example order detail) use their own dark palette.

---

## 5. Navigation (`core/router.dart`)

Redirect rule: not logged in goes to `/login`, unless on `/login`, `/signup`, `/verify`, `/forgot-password`, `/reset-password`, `/splash`. Logged in on `/login`, `/signup` or `/splash` goes to `/home`.

Routes **outside** the bottom bar (use these from screens that are themselves outside the shell, otherwise a second shell is created and the screen goes blank):

| Path | Screen |
|---|---|
| `/splash`, `/login`, `/signup`, `/verify`, `/forgot-password`, `/reset-password` | auth |
| `/ai-chat` | AI shopping assistant |
| `/product-view/:id` | product detail (standalone) |
| `/checkout` | payment screen (standalone) |
| `/product-edit` | add/edit product |
| `/order-success/:orderId` | order success |
| `/complete-products` | seller must complete product status and country |
| `/seller/:id` | public seller profile |
| `/dispute` | open a dispute (receives the order as `extra`) |

Routes **inside** the bottom bar (5 branches):

| Branch | Routes |
|---|---|
| Home | `/home`, `/home/product/:id`, `/home/notifications` |
| Categories | `/categories`, `/categories/:name` |
| Cart | `/cart`, `/cart/payment`, `/cart/confirmation` |
| Messages | `/messages`, `/messages/chat/:id` |
| Profile | `/profile` (seller hub or profile), `edit`, `address`, `shipping-config`, `add-product`, `referral`, `orders`, `orders/detail`, `payment-methods`, `favorites` |

---

## 6. Screens

| Group | Screens |
|---|---|
| Auth | splash, login, signup (role choice, KYC photos for sellers), verification code, forgot and reset password |
| Shopping | home, categories, category products, product detail (variants), cart (promo code), favorites, AI chat |
| Checkout | payment (wallet connect + escrow), confirmation, order success |
| Orders | order history, order detail (confirm receipt), dispute (photos + video evidence) |
| Messaging | conversations list, chat (order action bar inside the chat) |
| Seller | seller hub (products, balance), add/edit product (variants, media), shipping config, complete products, seller public profile |
| Account | profile, edit profile, shipping address, payment methods (payout wallets + withdrawal request), referral, notifications |

---

## 7. Talking to the backend

- All URLs come from `ApiConfig` (`baseUrl = <server>/api`, `socketUrl = <server>`).
- `ApiConfig.getImageUrl()` repairs old image URLs (raw IPs, local `uploads/` paths). Cloudinary URLs pass through unchanged.
- Most calls use plain `http` and do **not** send the `Authorization` header. The backend currently accepts that because most routes are public (this will change when the backend is secured, so centralise a small HTTP client that adds `Bearer <token>`).
- Socket events: emits `joinUserRoom`, `joinRoom`, `sendMessage`; listens to `newMessage` and `newNotification` (shows a local notification).
- AI: `AiChatService` posts `{ message, history }` to `/api/ai/chat` (keeps the last 10 messages) and reads `data.message` and `data.products`.
- Conversation id convention: `<buyerId>_<sellerId>`.

---

## 8. Order flow in the UI

1. Buyer picks a product (or the cart), enters a delivery address and country, optionally a promo code (`POST /promo/verify`).
2. Payment screen: connect wallet, pay through escrow, then `POST /orders` with the transaction hash. Status `PENDING_ADMIN`.
3. Admin (or the escrow event) moves it to `PENDING_SHIPPING`. Seller sees "Mark shipped" in the chat action bar (`PUT /orders/:id/ship`).
4. Status `SHIPPED`: buyer sees **Receipt** and **Dispute**; seller can set `DELIVERED_BY_SELLER`.
5. Receipt: `OrderDetailScreen._confirmReceipt()` calls the contract `confirmerLivraison(escrowId)`, then `PUT /orders/:id/receive`.
6. Dispute: `POST /disputes` (multipart). Admin resolves from the back office API.

The chat screen shows the status badge, the referral discount badge, and the action buttons by role and status.
`WAITING_BUYER_CONFIRMATION` is legacy; the shipping fee is now computed server-side at order creation.

Fees shown to the buyer: platform fee 3% of (items + shipping), minus the referral discount when the buyer was referred.

---

## 9. Blockchain: wallet and escrow

### Files
- `blockchain/wallet_service.dart`: WalletConnect v2 (`Web3App`). Project id is set in the file. Requires chain `eip155:56` with methods `eth_sendTransaction` and `personal_sign`. On web it shows a QR code. On mobile it lists installed wallets and opens a deep link.
- `blockchain/escrow_contract.dart`: `web3dart` wrapper with `getCommande`, `creerCommande`, `confirmerLivraison`, `ouvrirLitige`. Read calls go through the RPC URL.
- `blockchain/escrow_abi.dart`: ABI containing the constructor and these functions: `creerCommande`, `confirmerLivraison`, `demanderRemboursement`, `ouvrirLitige`, `getCommande`. **No events and no dispute-resolution function.**

### Current configuration in code

| Item | Value in code |
|---|---|
| Contract address | `0x12B564Cb42C04B4258ED45c5FE42280f96B52bF7` (comment says BSC Testnet) |
| RPC | `https://data-seed-prebsc-1-s1.binance.org:8545` (BSC **Testnet**) |
| WalletConnect chain | `eip155:56` (BSC **Mainnet**) |
| `creerCommande` chainId | `56` (comment says "BSC Testnet") |
| `confirmerLivraison`, `ouvrirLitige` chainId | `97` (BSC Testnet) |
| Backend listener | BSC Mainnet RPC |

The same chain must be used everywhere. Make it one constant (chain id, RPC, explorer, contract address), switchable by build flavor.

### Contract status codes
`getCommande` returns `statut` as `uint8`. The meaning of each value is defined in `PlexusEscrow.sol` (not provided). Add a Dart enum once confirmed.

### What happens today when the user taps "Pay via escrow"
`PaymentScreen._payerAvecWallet()`:
1. Requires a connected wallet and an address.
2. Takes `displayPrice` (a **USD** price) and passes it as `montantBNB`.
3. Calls `EscrowContract.creerCommande(privateKey: '', ...)`.
4. Puts the returned hash in a field and calls `_confirmTransfer()`, which posts the order.

### Gaps in the current implementation

These explain why on-chain payment cannot work yet.

1. **No signing path.** `EscrowContract` signs with `EthPrivateKey.fromHex(privateKey)` and every caller passes an empty string (comment: "handled by WalletConnect"). The WalletConnect session is created but never used to send a transaction, so the call fails. The app must never hold the user's private key. The transaction has to be sent **through the WalletConnect session** (`eth_sendTransaction` request with `from`, `to`, ABI-encoded `data`, `value`) and the wallet app signs it.
2. **No USD to BNB conversion.** The UI prints `$12.00 BNB`. The amount must be converted with a price source (backend endpoint or oracle) and shown in BNB, with a slippage margin for volatile prices.
3. **Float to wei.** `BigInt.from(montantBNB * 1e18)` loses precision. Use `EtherAmount.fromBigInt` from a decimal string, or `BigInt` math.
4. **Zero-address fallback.** If the seller wallet is missing, the code uses `0x000...000`. Funds sent there are lost. Block checkout when the seller has no valid wallet address.
5. **No receipt wait.** The app posts the order right after getting a hash, without waiting for confirmation or checking `status` of the receipt. Wait for the receipt, then call the backend.
6. **Swallowed errors on release.** In `_confirmReceipt()` an on-chain failure is only logged, then `/orders/:id/receive` is called anyway. The UI says delivered while funds may still be locked.
7. **`escrowId` is unknown to the client at pay time.** It comes from the `CommandeCreee` event (via the backend listener). Read it from the transaction receipt logs instead, or poll the order until `escrowId` is set before allowing "Receipt".
8. **Disputes are off-chain.** `DisputeScreen` only posts to the API. `ouvrirLitige` exists in Dart but is not called, and `demanderRemboursement` has no Dart wrapper.
9. **Session handling.** `WalletService` is created per screen and `init()` creates a new `Web3App` each time. Keep one app-wide instance, restore existing sessions, and handle `chainChanged` and `accountsChanged`.
10. **Payout wallets are different.** The "payment methods" screen stores withdrawal wallets (name, network, address) through `/users/:id/wallets`. The seller wallet used by escrow is `Product.sellerWallet`, selected when adding a product. Validate the address format (`0x` + 40 hex) in both places.

### Suggested target flow

1. Connect wallet, check `chainId` equals the configured chain (request a switch if not).
2. Get the BNB amount from the backend (server-side price and fee).
3. Encode `creerCommande(seller, days)` with the ABI and send `eth_sendTransaction` through WalletConnect with `value`.
4. Wait for the receipt, read the `CommandeCreee` event for `escrowId`.
5. Send `transactionHash` and `escrowId` to `POST /orders`.
6. On receipt: send `confirmerLivraison(escrowId)` through WalletConnect, wait, then let the backend listener mark the order delivered.

---

## 10. Localisation

- 10 languages: fr, en, es, it, de, pt, nl, ja, zh, ar (`lib/l10n/app_localizations_*.dart`).
- `L10n` picks the phone language; if unsupported, French-speaking countries fall back to French, others to English. The region is kept for date and number formats.
- Access strings through the global `l10n` getter. `main.dart` rebuilds the tree when the locale changes.
- The `.arb` files or generation config were not provided. Confirm whether strings are generated or edited by hand before adding new ones.
- Some texts are still hard-coded French or English (for example the `LITIGE` label and the `PAIEMENT` section title).

---

## 11. Deployment (web)

- Build: `flutter build web`, deploy the `build/web` folder to Vercel.
- A single `vercel.json` using `rewrites` to `/index.html` is required (two conflicting `vercel.json` files caused a blank screen before).
- Firebase web needs the correct `clientId` in `firebase_options.dart` for Google sign-in (a missing one caused 401 errors).
- Add the Vercel domain to the backend `allowedOrigins` and to the Firebase authorised domains.

---

## 12. Known issues and technical debt

- The escrow payment gaps in section 9 (blocking).
- Hard-coded values: WalletConnect project id, contract address, RPC, Firebase web options. Move to build-time configuration (`--dart-define` or flavors).
- No central HTTP client: each screen builds its own `http` call, with no token header, no timeout and little error handling.
- Prices are USD in the catalogue; the UI labels them with the crypto ticker. Define one currency model.
- `print()` statements in providers and wallet service; replace with a logger.
- Large screens (`home_screen`, `add_product_screen`, `cart_screen`, `chat_screen`) mix UI, API and business logic. Extract repositories and view models.
- Duplicated or dead code (see section 3).
- No automated tests.

---

## 13. Suggested next steps

1. Fix the escrow payment path (signing through WalletConnect, BNB amount, receipt, `escrowId`).
2. Unify network configuration with the backend (one chain, one address).
3. Add an API client with the auth header and token expiry handling.
4. Wire disputes and refunds to the contract.
5. Clean the repository (section 3) and add tests for cart, pricing and order status logic.