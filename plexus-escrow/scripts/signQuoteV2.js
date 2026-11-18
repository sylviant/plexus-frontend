// Signs a purchase quote with the operator key (what the PLEXUS server will do) so a buyer can call
// createOrder(quote, signature) by hand from BscScan / Remix / MetaMask on testnet.
//
//   PowerShell:
//     $env:BUYER="0xBuyerWallet"; $env:SELLER="0xSellerWallet"; npm run quote:testnet
//   optional: PRODUCT=100 DELIVERY=10 REFERRER=0x... INTERNATIONAL=true ORDER=my-order-1 VALID_MINUTES=60
//
// The deployer key must be the contract's operator (it is, with the default .env).
const fs = require("fs");
const path = require("path");
const { ethers, network } = require("hardhat");

const TYPES = {
  Quote: [
    { name: "orderRef", type: "bytes32" }, { name: "buyer", type: "address" }, { name: "seller", type: "address" },
    { name: "referrer", type: "address" }, { name: "productAmount", type: "uint256" },
    { name: "deliveryAmount", type: "uint256" }, { name: "feeBps", type: "uint16" },
    { name: "international", type: "bool" }, { name: "validUntil", type: "uint256" },
  ],
};

async function main() {
  const env = process.env;
  const info = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "deployments", `${network.name}.json`), "utf8"));
  const [signer] = await ethers.getSigners();
  if (signer.address.toLowerCase() !== info.operator.toLowerCase())
    throw new Error(`The signing key (${signer.address}) is not the contract operator (${info.operator}).`);
  for (const k of ["BUYER", "SELLER"]) if (!ethers.isAddress(env[k] || "")) throw new Error(`Set ${k}=0x... (a valid address)`);
  if (env.BUYER.toLowerCase() === env.SELLER.toLowerCase()) throw new Error("BUYER and SELLER must be different wallets");
  const referrer = env.REFERRER || ethers.ZeroAddress;
  if (!ethers.isAddress(referrer)) throw new Error("REFERRER is not a valid address");

  const escrow = await ethers.getContractAt("PlexusEscrowV2", info.escrow);
  const feeBps = Number((await escrow.feeConfig()).feeBps); // the quote must carry the CURRENT fee
  const now = (await ethers.provider.getBlock("latest")).timestamp;
  const orderName = env.ORDER || `order-${Date.now()}`;
  const q = {
    orderRef: ethers.id(orderName),
    buyer: env.BUYER, seller: env.SELLER, referrer,
    productAmount: ethers.parseEther(env.PRODUCT || "100"),
    deliveryAmount: ethers.parseEther(env.DELIVERY || "10"),
    feeBps,
    international: String(env.INTERNATIONAL).toLowerCase() === "true",
    validUntil: env.VALID_UNTIL ? Number(env.VALID_UNTIL) : now + Number(env.VALID_MINUTES || 60) * 60,
  };
  const domain = { name: "PlexusEscrow", version: "2", chainId: (await ethers.provider.getNetwork()).chainId, verifyingContract: info.escrow };
  const signature = await signer.signTypedData(domain, TYPES, q);

  // integrity check against the deployed contract
  const digest = await escrow.quoteDigest(q);
  const recovered = ethers.recoverAddress(digest, signature);
  if (recovered.toLowerCase() !== info.operator.toLowerCase()) throw new Error("signature does not recover to the operator");

  const total = q.productAmount + q.deliveryAmount;
  const tuple = [q.orderRef, q.buyer, q.seller, q.referrer, q.productAmount.toString(), q.deliveryAmount.toString(), String(q.feeBps), String(q.international), String(q.validUntil)];
  console.log(`Quote "${orderName}"  (${ethers.formatEther(q.productAmount)} + ${ethers.formatEther(q.deliveryAmount)} USDT, fee ${feeBps / 100}%)`);
  console.log(`Valid until ${new Date(q.validUntil * 1000).toISOString()}`);
  console.log(`Signature checked against the contract: OK (signer ${recovered})\n`);
  console.log(`orderRef (keep it, every later step needs it):\n${q.orderRef}\n`);
  const appJson = {
    orderRef: q.orderRef, buyer: q.buyer, seller: q.seller, referrer: q.referrer,
    productAmount: q.productAmount.toString(), deliveryAmount: q.deliveryAmount.toString(),
    feeBps: q.feeBps, international: q.international, validUntil: q.validUntil, signature,
  };
  console.log(`For the app (the JSON the backend will return), e.g. flutter run --dart-define=DEV_QUOTE_JSON='<this>':\n${JSON.stringify(appJson)}\n`);
  if (env.OUT) {
    // used to keep the Flutter tests honest: the app must encode exactly the same createOrder call as ethers
    fs.writeFileSync(env.OUT, JSON.stringify({
      note: "Signed by the real operator key for the deployed contract. Produced by plexus-escrow/scripts/signQuoteV2.js",
      escrow: info.escrow, chainId: Number((await ethers.provider.getNetwork()).chainId),
      quote: appJson, createOrderCalldata: escrow.interface.encodeFunctionData("createOrder", [q, signature]),
    }, null, 2));
    console.log(`Wrote ${env.OUT}\n`);
  }
  console.log(`createOrder -> q (tuple), paste as one line:\n${JSON.stringify(tuple)}\n`);
  console.log(`createOrder -> signature:\n${signature}\n`);
  console.log(`The buyer must first approve at least ${ethers.formatEther(total)} USDT (${total}) for ${info.escrow}`);
  console.log(`Helper: bytes32 of a text, e.g. carrier "DHL" = ${ethers.id("DHL")}`);
}

main().catch((e) => { console.error(e.shortMessage || e.message); process.exitCode = 1; });
