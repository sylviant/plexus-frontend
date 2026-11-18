// Verify an existing deployment (reads deployments/<network>.json).
//   npm run verify:testnet            (hardhat run scripts/verifyV2.js --network bscTestnet)
// deployV2.js already does this automatically; use this to retry or to verify an older deployment.
const fs = require("fs");
const path = require("path");
const { network } = require("hardhat");
const { verifyDeployment } = require("./lib/verifyV2");

async function main() {
  const file = path.join(__dirname, "..", "deployments", `${network.name}.json`);
  if (!fs.existsSync(file)) throw new Error(`No deployment found: ${file}. Run the deploy first.`);
  const info = JSON.parse(fs.readFileSync(file, "utf8"));
  const r = await verifyDeployment(info);
  const failed = [...Object.values(r.sourcify), ...Object.values(r.etherscan)].some((v) => v === false);
  if (failed) process.exitCode = 1;
}

main().catch((e) => { console.error(e.message); process.exitCode = 1; });
