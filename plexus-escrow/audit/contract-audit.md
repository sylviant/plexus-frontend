# PlexusEscrowV2: internal audit (tasks 2.8, 3.6, 3.8 and 4.7)

| | |
|---|---|
| Contract | `contracts/PlexusEscrowV2.sol` (868 lines), Solidity 0.8.24, optimizer 200 runs, EVM `shanghai`, OpenZeppelin 5.x |
| Deployed | BSC testnet, 18 Nov 2026: `0x9e7C2F8Fa9BfB341df08A50DA3377B88DB2DC82E` (source verified on Sourcify, exact match) |
| Reviewed | 18 Nov 2026 |
| Type | **Internal review, carried out with AI assistance (Claude Code) together with the contract's author. It is not an independent audit.** |
| Rules reviewed against | `PLEXUS-Order-Workflow.pdf` (flowcharts 1 to 7) and the Correction Plan, tasks 3.1 to 3.7 |

## 1. Verdict

- **No High-severity finding. No defect found that loses, locks for others, or misdirects user funds.**
- **One Low defect (F-04)** is proven by a test: after the treasury address is changed, the old treasury's balance below the $5 minimum cannot be withdrawn. No money is lost, and it is avoided by an operating rule or a one-line contract change. A decision is needed.
- **One Medium operational risk (F-01)** comes from the specification itself: a dispute is decided by the owner, and if the owner stays silent for 14 days the buyer is refunded in full. It is acknowledged and is not a code defect, but it must be controlled before real funds (multisig, alerting).
- The contract is **ready for real funds only when the conditions in section 6 are met.** The most important ones are that the owner is a multisig and that this report is signed.

## 2. Evidence

| Evidence | Result |
|---|---|
| Unit tests (`npm test`) | **80 pass**; 100% of lines, 92.8% of branches. Includes every business-rule example from the workflow document, every deadline boundary one second either side, unusual tokens (fee on transfer, re-entering token, a token that blocks a payee), smart-contract wallets. |
| Randomised invariant test (`test/PlexusEscrowV2.invariant.test.js`) | **13 runs, about 4,950 random actions** (orders, shipping, disputes, returns with postage, adjustments, withdrawals, fee changes, pauses, time jumps). After **every** action: the contract's token balance equals `totalHeld`, and `totalHeld` equals every credit owed plus all money locked in open orders. **All hold.** |
| Planted-bug check | 4 deliberately planted accounting bugs (1 wei too much paid to a seller; 1 wei of postage too much to a buyer; 1 wei too much postage returned to a seller; 1 wei too little taken from a seller's earnings) were **each caught** by the invariant test. The first version of the test missed the postage bugs, so a return-heavy mode was added. The contract was restored byte-identical each time. |
| Static analysis (Slither 0.10.0) | 26 results, **0 High**, all reviewed (section 7). |
| Misuse on the deployed testnet contract (`scripts/misuseTestnet.js`) | **50 of 50 forbidden actions were refused with the expected error**: stranger and ordinary accounts calling owner, operator, buyer and seller functions; the owner exceeding its powers (fee above 10%, renouncing, zero addresses, taking customer money with `rescueExcess`); payment attacks (expired, altered, wrongly signed, wrong-fee, replayed quotes; paying for someone else; buying from yourself; zero price). Saved in `misuse-attempts-bscTestnet.json`. |
| On-chain flows on BSC testnet | Smoke test; full test (59 checks); real-wallet (MetaMask) tests of payment, delivery confirmation, a delivery-fee change, a dispute with owner decision, and a refund; the plan's $100 + $15 referral example (seller 113, referrer 0.60, buyer 0.40, PLEXUS 1.00, all 115 accounted for; `referral-example-bscTestnet.json`). The contract held exactly what it owed after every step. |
| 39-rule check on a deployed copy (`npm run verify:local`) | 39 of 39, with time travel for every deadline. |

## 3. Checklist from the plan (task 3.8)

### A. Access control
| Check | Result | Where |
|---|---|---|
| Owner-only functions: `extendDispute`, `resolveDispute`, `approveReturn`, `resolveWrongAddress`, `setOperator`, `setTreasury`, `pause`, `unpause`, `proposeFeeConfig`, `cancelFeeConfig`, `rescueExcess` | Pass | lines 465, 478, 506, 533, 684, 690, 697, 701, 706, 724, 732; refused for non-owners in tests and on testnet |
| Operator-only: `setVerified` | Pass | line 677 |
| Every order function checks that the caller is the buyer or the seller before it checks the state | Pass | e.g. 311, 338, 376, 401, 418, 436, 449, 459, 553 |
| Ownership moves in two steps; renouncing is disabled | Pass | `Ownable2Step`; line 740 |
| The signature is the server's only: a quote signed by anyone else, or altered after signing, or for another buyer, chain or contract, is refused | Pass | lines 268 to 300 (EIP-712, OpenZeppelin `ECDSA.recover` rejects malleable signatures) |

### B. Payout and refund paths
| Check | Result | Where |
|---|---|---|
| Nobody is paid automatically: every payout is a withdrawal by the owner of the balance, so a refusing wallet blocks nobody | Pass | 642 to 672; tested with a blocked payee |
| Refunds are always paid in full with no minimum, even while paused; earnings and rewards need $5; rewards need the identity check | Pass | 642 to 672 |
| The contract pulls exactly what it is owed: a token that delivers less is refused | Pass | `_pull`, line 818 |
| Reentrancy: every function that moves tokens or credits is guarded, and balances are changed before tokens leave | Pass | `nonReentrant` on all of them; tested with a re-entering token in both directions |
| Every order ends in exactly one terminal state, and the credits created equal the money paid in | Pass | `_settle` 834, `_refundAll` 826, `resolveWrongAddress` 533; the invariant test |
| A deadline never leaves funds without a way out: each state has a timeout path | Pass | `refundUnshipped`, `expireDeliveryAdjustment`, `release`, `resolveExpiredDispute`, `finalizeReturn` |

### C. Fee and referral snapshot
| Check | Result | Where |
|---|---|---|
| The fee and the 30/20 shares are copied onto the order at payment, so a later change never touches it | Pass | `_storeOrder`, lines 791 to 815; tested |
| A quote must carry the current fee | Pass | line 274 |
| Commission is 2% of the product the seller keeps; delivery, refunded amounts and return costs carry none | Pass | `_settle`, lines 844 to 861; rounding tested |
| 30% referrer / 20% buyer / remainder PLEXUS (dust included); no referrer: 100% PLEXUS; referrer is the seller: 0 / 20 / 80 | Pass | lines 845 to 858; verified on testnet |
| The referrer is locked at the buyer's first order; self-referral refused | Pass | `_lockReferrer`, line 778 (see F-03) |
| Rewards are credited only when an order settles, never for a refunded order | Pass | `_settle` only |

### D. Owner and multisig powers
| The owner **can** | The owner **cannot** (tested) |
|---|---|
| decide one disputed order at a time (buyer wins, seller wins, split), extend it once, approve a return, decide a wrong-address case | move money outside an order's own amount; touch another order or any balance |
| change the operator and the treasury (immediately, see F-02) | change an existing order's fee or referral split |
| pause **new orders** | stop withdrawals, shipping, disputes or settlement |
| propose a fee up to 10% with a 48-hour wait, for new orders only | skip the wait or exceed the cap |
| send to the treasury only tokens that exceed what is owed (`rescueExcess`) | take owed money (refused with `NothingToWithdraw`) |
| | renounce ownership |

The multisig itself **does not exist yet** (on testnet the owner is one wallet that also holds the operator and treasury roles). Creating it is a condition in section 6.

### E. Time rules
| Rule | Constant | Result |
|---|---|---|
| Ship within 7 days, then a free refund that anyone can trigger | `SHIP_WINDOW` | Pass, boundary tested; the two paths never overlap |
| Release after 14 days (30 international), counted from shipping, backdating cannot shorten it | `RELEASE_WINDOW_*` | Pass |
| Delivery-fee change answered within 5 days; fresh 7-day shipping window on acceptance | `ADJUSTMENT_WINDOW` | Pass; also on testnet with a real wallet |
| Dispute decided within 14 days, one extension of 14; then the buyer is refunded in full | `DISPUTE_*` | Pass |
| Returns: 3 days to fund postage, 7 to ship back, 14 (30 international) to confirm or contest | `RETURN_*` | Pass |
| Fee changes wait 48 hours and apply to new orders only | `FEE_TIMELOCK` | Pass |

## 4. Findings

| ID | Severity | Finding | Recommendation | Status |
|---|---|---|---|---|
| **F-01** | Medium (operational) | Disputes depend on the owner being available. If the owner does not decide within 14 days (28 with the extension) the buyer is refunded in full, even when the seller was right. This is what the specification asks for, so it is not a code defect, but a lost or unavailable key makes every dispute go to the buyer. | Make the owner a multisig with several active signers; alert on every `DisputeOpened` event; keep the recovery procedure written down; consider a reminder bot at day 10. | Acknowledged (specified). Open until the multisig and alerting exist. |
| **F-02** | Low | `setOperator` and `setTreasury` take effect at once, with no waiting period (lines 684 to 695). A compromised owner could swap the operator or redirect new commissions immediately. | With a multisig owner the risk is small. Optionally add a 48-hour delay like the fee change. | Open (decision) |
| **F-03** | Low | The referrer is fixed forever by the first quote a buyer pays (line 778). If the server sends the wrong referrer on a buyer's first order, nothing on-chain can correct it. | The backend must send the user's registered referrer, and must have a test for it. Write the operator runbook. | Open (backend, task 2.5) |
| **F-04** | Low | After `setTreasury`, the OLD treasury is no longer exempt from the $5 minimum (line 655), so a balance of it below $5 cannot be withdrawn. Proven by the test "F-04". The money stays owed and counted; changing the treasury back restores access. | Rule: withdraw the treasury balance before changing the address. Or make `setTreasury` move the old balance to the new treasury. | **Open (decision needed)** |
| **F-05** | Low | The operator can set a user's `verified` flag to false, which blocks that user's reward withdrawals (not earnings or refunds). | Acknowledge as part of the operator's trust. Log every change; the backend should only do this for a documented reason. | Acknowledged |
| **F-06** | Info | Nothing on-chain stops the owner or operator from also buying or selling. On testnet one wallet holds every role on purpose. | Policy: multisig signers and the operator key must never trade. | Acknowledged |
| **F-07** | Info | The contract assumes an ordinary 18-decimal token: no fee on transfer, no hooks, no blacklist, and `minWithdrawal` is in the token's smallest unit. A fee token is refused, a hook token cannot re-enter, and a blocked payee blocks nobody else (all tested). | Before mainnet, check the real BSC-USD contract (decimals, owner powers, blacklist). | Open (mainnet check) |
| **F-08** | Info | Compiler 0.8.24 and EVM `shanghai`. | Re-check the compiler's published bug list, and confirm BNB Smart Chain mainnet supports the `shanghai` EVM (the testnet deployment works). | Open (mainnet check) |
| **F-09** | Info | `executeFeeConfig` can be called by anyone once the wait is over. | Intended. | Closed |
| **F-10** | Info | 20 timestamp comparisons; the shortest window is 3 days. | Accepted (see section 7). | Closed |

## 5. Not covered

The OpenZeppelin library code (assumed correct), the economics of the fee, the backend and the app, the custody of the operator key, and the multisig's own security. This is not a substitute for an independent audit.

## 6. Conditions before the contract holds real funds

1. **Owner is a multisig** (Safe, 2 of 3, hardware-key signers) with a written, tested recovery procedure. Rehearse a dispute decision through it. (Task 3.2)
2. **This report is signed** (below), and F-04 is decided.
3. **The operator key** lives in a secrets manager, not in a developer's wallet, and is different from the owner and the treasury.
4. **Mainnet token checked** (F-07) and the deployment script run with the real address; `minWithdrawal` confirmed in the token's units.
5. **EVM and compiler checked** for mainnet (F-08).
6. **Alerts** on `DisputeOpened`, `FeeConfigProposed`, `OperatorChanged`, `TreasuryChanged` and `Paused` (F-01, F-02).
7. **The backend sends the right referrer** on first orders (F-03), with a test.
8. **A small real-money run** (a purchase and a refund) is done before volume.
9. Strongly recommended: **an independent review** of the contract.

## 7. Static analysis (task 3.6)

Slither 0.10.0 (93 detectors), run on 18 Nov 2026 against the source deployed to BSC testnet. Test helpers and the mock token are excluded (`slither.config.json`). Repeat with `npx hardhat compile --force` then `npm run analyze`.

**26 results. 0 High. 4 Medium (all reviewed, none a defect). 20 Low (expected). 2 Informational.** No detector for reentrancy, unchecked token transfers, arbitrary `transferFrom`, `delegatecall`, `selfdestruct`, `tx.origin`, uninitialised storage or access control reported anything.

| Finding | Count | Verdict | Reason |
|---|---|---|---|
| `timestamp` comparisons | 20 | Accepted | Deadlines are the purpose of the contract; the shortest window is 3 days, the fee wait 48 hours. A validator can move a timestamp by seconds only. |
| `divide-before-multiply` in `_settle` | 2 | Accepted, by design | The commission is rounded down once; referrer and cashback shares are percentages of the commission actually charged. Dust stays with PLEXUS. The test "rounding: every wei is accounted for" shows credits always add up to the amount paid. |
| `incorrect-equality` `excess == 0` in `rescueExcess` | 1 | Accepted | A guard that refuses to send zero. The function sends only what exceeds `totalHeld`, never owed money. |
| `incorrect-equality` `pendingFeeEta == 0` in `executeFeeConfig` | 1 | Accepted | A "no change pending" marker; cannot be influenced from outside. |
| `solc-version` (0.8.24) | 2 | Informational | Generic note; re-check the compiler's bug list before mainnet (F-08). |

Static analysis finds code patterns only; the business rules are covered by the 80 unit tests, the invariant test, the 39-rule check and the on-chain tests.

## 8. Payment flow (task 2.8): contract and app side

**Passed for the contract and the app's wallet module.** The server's records cannot be compared yet, because the backend does not use the V2 contract (Sylviant's part).

Payments were made from a real MetaMask wallet through the app's wallet module, with a server-format quote signed by the real operator key, then read back from the chain.

| Order | What was done | Blockchain showed |
|---|---|---|
| 1 | Pay, ship, confirm ($100 + $10) | Same buyer, seller, amounts and 2% fee; seller **108**, PLEXUS **2** |
| 2 | Pay, ship, dispute, owner decides for buyer, refund withdrawn | Refunded **110**; buyer balance back to its earlier value |
| 3 | Pay, delivery change 10 to 25 accepted, ship, confirm | Only the **$15 difference** approved; shipping window reset to 7 days; seller **123**, PLEXUS **2** |
| Plan example | $100 + $15 with a referrer, fresh wallets | Seller **113**, referrer **0.60**, buyer **0.40**, PLEXUS **1.00**; all 115 accounted for |

Plan items: amounts, order matching (contract side), referral shares, refund, dispute, delivery adjustment and exact approval (never unlimited, no allowance left) all pass. A rejected approval is covered by automated tests with a fake wallet, not by a real click. Comparing the server's records is **not possible yet**.

App code review (`lib/blockchain/v2/`): the app never holds a private key; before the wallet is asked it checks that the wallet is connected and is the quote's buyer, that the quote is not expired (60 s margin) and that the balance is enough; the approval is exactly the total and the order is created only after the approval is visible on-chain; a payment that went through is never reported as failed because the server did not answer. No open finding. The old module (`escrow_contract.dart`, `wallet_service.dart`) holds private-key methods and the wrong network, is marked `@Deprecated` and must be deleted when the screens move to V2.

Open, not Ranjith's: payment and order screens (2.1), quote endpoint (2.2), V2 listener (2.4), server fee and referral logic, still 3% (2.5), comparison of server records with the chain. Ranjith: WalletConnect from a phone not yet tried.

## 9. Launch readiness (task 4.7)

**Verdict: NO-GO for real money.** The contract is ready for the next step (multisig and accepted report). The launch is blocked by the multisig, the V2 backend and payment screens, the live environment and open secrets. Continue on testnet.

| Area | Status |
|---|---|
| Tests: contract (80 unit, 13 invariant runs, Slither, 50/50 misuse, on-chain) and app wallet module (51 Flutter tests) | **Done** |
| Backend suite and CI (89 of 93 pass; `ci.yml` has two workflows, no test or lint script); attack replay on staging | Open / blocked (Sylviant) |
| Backups and restore; cents migration dry run on live-data copy | Open (Sylviant) |
| Alert channel and stuck-payment alert | Open (Sylviant) |
| Contract event alerts (`DisputeOpened`, `FeeConfigProposed`, `OperatorChanged`, `TreasuryChanged`, `Paused`); keeper bot (3.3) | Open (Ranjith) |
| Firebase admin key out of git and revoked; Gmail app password revoked; all `.env` keys and `JWT_SECRET` rotated; git history scanned and purged; admin accounts | Open (Sylviant) |
| `ALLOWED_ORIGINS`, `NODE_ENV=production`, mainnet address, chain id, start block | Blocked (needs mainnet contract) |
| Owner is a multisig (3.2) | Blocked (Ranjith) |
| Deployer, owner, operator and treasury are different keys; operator key in a secrets manager | Open (Ranjith) |
| Real-money test (pay, ship, confirm, refund, double tap creates one order) | Blocked: screens and backend not on V2. The same flows passed on testnet through the wallet module. |

Mainnet deployment order (only after the blockers are cleared):
1. Report accepted, F-04 decided, conditions 1 to 9 of section 6 met.
2. Create the Safe (2 of 3, hardware keys); rehearse a dispute decision through it on testnet.
3. Check the real BSC-USD contract (address, 18 decimals, no fee, no hooks, owner powers); confirm compiler and `shanghai` for mainnet.
4. Deploy with the real token, the Safe as owner, a dedicated operator key, the treasury wallet, fee 200 / 3000 / 2000 and `minWithdrawal` = 5 tokens in the token's units (the script refuses mainnet today on purpose).
5. Verify the source; read back `owner`, `operator`, `treasury`, `token`, `feeConfig`, `minWithdrawal`, `paused`.
6. Point backend and app at the mainnet address; set `ESCROW_START_BLOCK`.
7. A small real-money purchase and refund through the whole stack; `reconcile` must say OK.
8. Only then, volume.

Order of work to reach GO: (1) Sylviant: secrets and history, CI, staging and backups; (2) Sylviant: quote endpoint, V2 listener, server money rules, screens; (3) Ranjith: multisig and rehearsal, keeper bot and alerts, decide F-04; (4) both: re-run the full testnet flow from app and server; (5) accept this report, then the deployment order above.
