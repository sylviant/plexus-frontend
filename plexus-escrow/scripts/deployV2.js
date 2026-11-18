const fs = require("fs");
const path = require("path");
const { deployAll } = require("./lib/deployV2");
const { verifyDeployment } = require("./lib/verifyV2");

async function main() {
  const { _localSigners, ...info } = await deployAll();
  if (info.network === "hardhat") return console.log("(in-process network: nothing saved)");
  const dir = path.join(__dirname, "..", "deployments");
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `${info.network}.json`);
  fs.writeFileSync(file, JSON.stringify(info, null, 2));
  console.log(`Saved ${file}`);

  // Public networks: verify the source (Sourcify automatically, BscScan bundle/API). Set SKIP_VERIFY=1 to skip.
  if (!process.env.SKIP_VERIFY) await verifyDeployment(info);

  if (info.mockDeployed) {
    console.log(`\nNext: put the test token in .env so a redeploy reuses it:\n  TOKEN_ADDRESS=${info.token}`);
  }
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
