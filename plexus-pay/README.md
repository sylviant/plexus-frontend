# plexus-pay

Hosted wallet and escrow payment page of PLEXUS.
React + Vite + TypeScript + **Thirdweb SDK** (same technology as the reference project, current v5 line).

It is opened by the Flutter app (web and mobile) and does one thing: let the user connect a wallet and send one escrow transaction.

| Action (`a=`) | Contract call | Backend event checked |
|---|---|---|
| `pay` (default) | `creerCommande(seller, days)` with the BNB amount | `CommandeCreee` |
| `confirm` | `confirmerLivraison(escrowId)` | `LivraisonConfirmee` |
| `dispute` | `ouvrirLitige(escrowId)` | `LitigeOuvert` |
| `refund` | `demanderRemboursement(escrowId)` | `Rembourse` |

The page has no price, chain or contract in its code. It reads them from `GET /api/escrow/orders/:id/payment-info`.
It trusts nothing: after the transaction the backend re-checks it on-chain.

## Link format

`https://<pay-site>/?orderId=<id>&a=pay&r=<returnUrl>#t=<sessionToken>`

The token is in the fragment, it is read once and removed from the address bar. Links are created by `POST /api/escrow/orders/:id/session` (30 minutes).

## Setup

```bash
npm install
cp .env.example .env     # fill it
npm run dev
npm run build            # type-check + production build in dist/
```

| Variable | Purpose |
|---|---|
| `VITE_THIRDWEB_CLIENT_ID` | thirdweb dashboard, Settings, API Keys |
| `VITE_API_URL` | backend base URL including `/api` |
| `VITE_APP_URL` | the real public URL of this site (shown in the wallet) |
| `VITE_WC_PROJECT_ID` | optional own Reown (WalletConnect) project id |
| `VITE_ALLOWED_RETURN` | allowed prefixes for the "Return to PLEXUS" button |

## Deploy (Vercel)

1. Import the folder as a Vite project. `vercel.json` already rewrites every path to `/`.
2. Add the variables above. Put `public/logo.png` (square PNG) in the project: it is the icon wallets display.
3. In the thirdweb dashboard, allow the domain of this site for your API key.
4. In the backend, set `PAY_SITE_URL` to this site and add its domain to `allowedOrigins`.
5. To remove the "Domain not valid" warning shown by wallets: set `VITE_APP_URL` to the real domain, and register the same domain in your Reown (WalletConnect) project, then pass its id in `VITE_WC_PROJECT_ID`.

## Wallets

MetaMask, Trust Wallet, Binance Wallet, Coinbase, Rainbow, SafePal, OKX, Crypto.com, Rabby and generic WalletConnect (list in `src/App.tsx`).
Add a wallet by adding one `createWallet('<id>')` line, ids are in thirdweb's wallet list.

## Files

```
src/main.tsx       ThirdwebProvider
src/App.tsx        page: summary, ConnectButton, send transaction, report to backend
src/config.ts      client, env, allowed return URLs
src/api.ts         3 backend calls
src/escrowAbi.ts   contract method signatures
```
