# PLEXUS Frontend (Flutter)

Mobile and web client of the PLEXUS marketplace.
Buyers and sellers browse products, chat, order and pay in USDT through the PlexusEscrowV2 escrow smart contract on BNB Smart Chain. The user's own wallet signs every payment; the app never holds a key.

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
    v2/                        PlexusEscrowV2 wallet module (see v2/README.md)
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
2. Payment screen: connect wallet. The app creates the order (`POST /orders`, product ids and quantities only; the server sets all prices; status `PENDING_PAYMENT`), asks the server for a signed quote, and pays it on the V2 contract (approve USDT for the exact total, then create the order on-chain).
3. The server's V2 listener sees the payment and moves the order forward. Seller sees "Mark shipped" in the chat action bar (`PUT /orders/:id/ship`).
4. Status `SHIPPED`: buyer sees **Receipt** and **Dispute**; seller can set `DELIVERED_BY_SELLER`.
5. Receipt: `OrderDetailScreen._confirmReceipt()` sends `confirmReceipt` to the V2 contract through the buyer's wallet; the contract releases the money to the seller. Delivery-fee changes from the seller are accepted in the payment screen, which pays only the difference.
6. Dispute: `POST /disputes` (multipart). The owner decides it on-chain; the contract refunds the buyer in full if nobody decides in time.

The chat screen shows the status badge, the referral discount badge, and the action buttons by role and status.

Fees: the contract takes 2% of the product price only (not delivery); the buyer sees the amounts from the server's quote.

---

## 9. Blockchain: wallet and escrow

The app pays through **PlexusEscrowV2** (BSC USDT). The wallet module is `lib/blockchain/v2/`; read `lib/blockchain/v2/README.md`
for the files, the one call a screen makes (`EscrowPaymentFlow.payOrder(orderId)`) and the quote format the backend must sign.
The app never holds a private key. The chain, contract and token come from one setting (`EscrowV2Config`, generated from the
deployment).

### Screens
`PaymentScreen` and `OrderDetailScreen` use the V2 module through `EscrowSession` (one wallet connection for the app).
The old V1 files are deleted. Payment needs the backend quote endpoint (`POST /escrow/orders/:id/quote`);
see the "How the screens use it" section of `lib/blockchain/v2/README.md`.

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

- Paying needs the backend quote endpoint (`POST /escrow/orders/:id/quote`) and its V2 listener (tasks 2.2, 2.4). Until then, a payment attempt fails with a server error.
- WalletConnect from a phone has not been tried with a real device; the browser wallet (MetaMask) path has. `walletconnect_flutter_v2` is deprecated in favour of Reown AppKit.
- Hard-coded values: WalletConnect project id (overridable with `--dart-define=WC_PROJECT_ID`), Firebase web options. The chain, contract, token and RPC come from `EscrowV2Config` (generated from the deployment, overridable with `--dart-define`).
- No central HTTP client: most screens build their own `http` call, with no timeout and little error handling. The payment screen sends the token; others may not.
- Prices are USD in the catalogue and USDT is treated as one dollar. Define one currency model.
- `print()` statements in providers; replace with a logger.
- Large screens (`home_screen`, `add_product_screen`, `cart_screen`, `chat_screen`) mix UI, API and business logic. Extract repositories and view models.
- Duplicated or dead code (see section 3).
- Tests exist for the wallet module only (`flutter test test/blockchain`, 51 tests).

---

## 13. Suggested next steps

1. Backend: quote endpoint and V2 listener, then pay a test order from the app end to end.
2. Try WalletConnect from a phone.
3. Wire disputes, delivery-fee changes and withdrawals (`withdraw`, `withdrawRefund`) to the V2 module.
4. Add an API client with the auth header and token expiry handling.
5. Clean the repository (section 3) and add tests for cart, pricing and order status logic.
