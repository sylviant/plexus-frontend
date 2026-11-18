// "Try every action that must fail" (task 3.8) against the DEPLOYED contract. Every attempt is a read-only simulation
// (eth_call): nothing is sent, nothing is paid, and each one must be refused with the expected error.
//   ORDER_REF=0x... SELLER_KEY=0x... npx hardhat run scripts/misuseTestnet.js --network bscTestnet
// ORDER_REF is any existing order (its state does not matter: the caller checks come first).
// SELLER_KEY is any funded or unfunded throwaway key that is NOT the owner/operator (a plain non-privileged account).
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");

const ZERO = ethers.ZeroAddress;
const QUOTE_TYPES = {
  Quote: [
    { name: "orderRef", type: "bytes32" }, { name: "buyer", type: "address" }, { name: "seller", type: "address" },
    { name: "referrer", type: "address" }, { name: "productAmount", type: "uint256" }, { name: "deliveryAmount", type: "uint256" },
    { name: "feeBps", type: "uint16" }, { name: "international", type: "bool" }, { name: "validUntil", type: "uint256" },
  ],
};

async function main() {
  const dep = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "deployments", `${network.name}.json`), "utf8"));
  const [owner] = await ethers.getSigners(); // owner = operator = treasury on this testnet
  const escrow = await ethers.getContractAt("PlexusEscrowV2", dep.escrow);
  const iface = escrow.interface;
  const ref = process.env.ORDER_REF;
  if (!/^0x[0-9a-fA-F]{64}$/.test(ref || "")) throw new Error("Set ORDER_REF=0x... (an existing order)");
  const stranger = ethers.Wallet.createRandom().connect(ethers.provider);
  const plain = new ethers.Wallet(process.env.SELLER_KEY, ethers.provider); // a non-privileged account
  const H = ethers.id("x");
  const chainId = (await ethers.provider.getNetwork()).chainId;
  const domain = { name: "PlexusEscrow", version: "2", chainId, verifyingContract: dep.escrow };
  const now = (await ethers.provider.getBlock("latest")).timestamp;
  const fee = Number((await escrow.feeConfig()).feeBps);
  const goodQuote = { orderRef: ethers.id(`misuse-${Date.now()}`), buyer: owner.address, seller: plain.address, referrer: ZERO,
    productAmount: ethers.parseEther("10"), deliveryAmount: 0n, feeBps: fee, international: false, validUntil: now + 3600 };
  const sign = (q, s = owner) => s.signTypedData(domain, QUOTE_TYPES, q);

  const name = (e) => {
    try { return iface.parseError(e.data)?.name; } catch { /* fall through */ }
    const m = String(e.message || "").match(/0x[0-9a-fA-F]{8}/g) || [];
    for (const sel of m) { const f = iface.getError(sel); if (f) return f.name; }
    return `unknown (${String(e.shortMessage || e.message).slice(0, 60)})`;
  };

  const attempts = [];
  const add = (who, label, signer, fn, args, expected) => attempts.push({ who, label, signer, fn, args, expected });

  // ---- a stranger tries owner, operator, buyer and seller powers
  const S = stranger;
  for (const [fn, args] of [
    ["setOperator", [stranger.address]], ["setTreasury", [stranger.address]], ["pause", []], ["unpause", []],
    ["proposeFeeConfig", [300, 0, 0]], ["cancelFeeConfig", []], ["extendDispute", [ref]], ["resolveDispute", [ref, 0, 0]],
    ["approveReturn", [ref, 5, 0]], ["resolveWrongAddress", [ref, 0]], ["rescueExcess", []], ["transferOwnership", [stranger.address]],
  ]) add("stranger", `${fn} (owner only)`, S, fn, args, "OwnableUnauthorizedAccount");
  add("stranger", "setVerified (operator only)", S, "setVerified", [stranger.address, true], "NotOperator");
  for (const [fn, args, err] of [
    ["confirmReceipt", [ref], "NotBuyer"], ["openDispute", [ref, H], "NotBuyer"], ["withdrawDispute", [ref], "NotBuyer"],
    ["acceptDeliveryAdjustment", [ref], "NotBuyer"], ["declineDeliveryAdjustment", [ref], "NotBuyer"], ["markReturnShipped", [ref, H, H, H, 0], "NotBuyer"],
    ["cancelBySeller", [ref], "NotSeller"], ["markShipped", [ref, H, H, H, 0], "NotSeller"], ["proposeDeliveryAdjustment", [ref, 1, H], "NotSeller"],
    ["concedeDispute", [ref], "NotSeller"], ["fundReturnPostage", [ref], "NotSeller"], ["confirmReturnReceived", [ref], "NotSeller"], ["contestReturn", [ref, H], "NotSeller"],
    ["withdraw", [], "NothingToWithdraw"], ["withdrawRefund", [], "NothingToWithdraw"], ["withdrawRewards", [], "NotVerified"],
  ]) add("stranger", `${fn}`, S, fn, args, err);

  // ---- an ordinary account (neither owner nor operator) tries privileged actions
  add("non-owner account", "resolveDispute (owner only)", plain, "resolveDispute", [ref, 0, 0], "OwnableUnauthorizedAccount");
  add("non-owner account", "rescueExcess (owner only)", plain, "rescueExcess", [], "OwnableUnauthorizedAccount");
  add("non-owner account", "proposeFeeConfig (owner only)", plain, "proposeFeeConfig", [500, 1000, 1000], "OwnableUnauthorizedAccount");
  add("non-operator account", "setVerified (operator only)", plain, "setVerified", [plain.address, true], "NotOperator");

  // ---- the OWNER tries to go beyond its powers
  add("owner", "fee above the 10% cap", owner, "proposeFeeConfig", [1001, 0, 0], "InvalidFeeConfig");
  add("owner", "referral shares above 100% of the commission", owner, "proposeFeeConfig", [300, 6000, 5000], "InvalidFeeConfig");
  add("owner", "renounce ownership", owner, "renounceOwnership", [], "RenounceDisabled");
  add("owner", "set the operator to nobody", owner, "setOperator", [ZERO], "ZeroAddress");
  add("owner", "set the treasury to nobody", owner, "setTreasury", [ZERO], "ZeroAddress");
  add("owner", "apply a fee change that was never proposed", owner, "executeFeeConfig", [], "NoPendingFeeConfig");
  add("owner", "cancel a fee change that does not exist", owner, "cancelFeeConfig", [], "NoPendingFeeConfig");
  add("owner", "take customer money with rescueExcess (nothing exceeds what is owed)", owner, "rescueExcess", [], "NothingToWithdraw");
  add("owner", "decide a dispute on an order that is not disputed", owner, "resolveDispute", [ref, 0, 0], "WrongStatus");

  // ---- payment attacks on createOrder
  const q1 = { ...goodQuote, orderRef: ethers.id(`m1-${Date.now()}`) };
  add("stranger", "pay a quote made for someone else", S, "createOrder", [q1, await sign(q1)], "NotBuyer");
  const q2 = { ...goodQuote, orderRef: ethers.id(`m2-${Date.now()}`), validUntil: now - 10 };
  add("buyer", "pay an expired quote", owner, "createOrder", [q2, await sign(q2)], "QuoteExpired");
  const q3 = { ...goodQuote, orderRef: ethers.id(`m3-${Date.now()}`) };
  const sig3 = await sign(q3);
  add("buyer", "pay a quote whose amount was changed after signing", owner, "createOrder", [{ ...q3, productAmount: 1n }, sig3], "BadSignature");
  const q4 = { ...goodQuote, orderRef: ethers.id(`m4-${Date.now()}`) };
  add("buyer", "pay a quote signed by an ordinary account, not the server key", owner, "createOrder", [q4, await sign(q4, plain)], "BadSignature");
  const q5 = { ...goodQuote, orderRef: ethers.id(`m5-${Date.now()}`), feeBps: fee + 100 };
  add("buyer", "pay a quote with an outdated fee", owner, "createOrder", [q5, await sign(q5)], "FeeMismatch");
  const q6 = { ...goodQuote, orderRef: ethers.id(`m6-${Date.now()}`), seller: owner.address };
  add("buyer", "buy from yourself", owner, "createOrder", [q6, await sign(q6)], "InvalidSeller");
  const q7 = { ...goodQuote, orderRef: ethers.id(`m7-${Date.now()}`), productAmount: 0n };
  add("buyer", "pay a quote with a zero price", owner, "createOrder", [q7, await sign(q7)], "InvalidAmount");
  const q8 = { ...goodQuote, orderRef: ref };
  add("buyer", "pay the same order number twice (replay)", owner, "createOrder", [q8, await sign(q8)], "OrderExists");

  const results = [];
  for (const a of attempts) {
    let outcome, ok = false;
    try {
      await escrow.connect(a.signer)[a.fn].staticCall(...a.args);
      outcome = "SUCCEEDED (it should have failed)";
    } catch (e) {
      outcome = name(e);
      ok = outcome === a.expected;
    }
    results.push({ who: a.who, attempt: a.label, expected: a.expected, got: outcome, ok });
    console.log(`${ok ? "OK  " : "FAIL"} ${a.who.padEnd(20)} ${a.label.padEnd(66)} -> ${outcome}`);
  }
  const bad = results.filter((r) => !r.ok);
  console.log(`\n${results.length - bad.length} of ${results.length} attempts were refused with the expected error`);
  const out = path.join(__dirname, "..", "audit", `misuse-attempts-${network.name}.json`);
  fs.writeFileSync(out, JSON.stringify({ contract: dep.escrow, network: network.name, ranAt: new Date().toISOString(), results }, null, 2));
  console.log(`Saved ${out}`);
  if (bad.length) process.exitCode = 1;
}

main().catch((e) => { console.error(e.shortMessage || e.message); process.exitCode = 1; });
