// Contract verification for a public-network deployment.
//
//  1. Always writes a bundle for BscScan's "Verify & Publish" web form (deployments/verify/<network>/).
//     A free Etherscan API key cannot verify BSC testnet through the API, so the form is the way in.
//  2. Verifies on Sourcify automatically (no API key needed, chain 97 and 56 supported).
//  3. Also verifies on BscScan through the API when the Etherscan plan supports the chain.
//
// Never throws: a failed verification must not look like a failed deployment.
const fs = require("fs");
const path = require("path");
const hre = require("hardhat");
const { ethers, run, artifacts } = hre;

const SUPPORTED = { bscTestnet: { chainId: 97, scan: "https://testnet.bscscan.com" }, bsc: { chainId: 56, scan: "https://bscscan.com" } };
const CONSTRUCTOR_TYPES = ["address", "address", "address", "address", "uint16", "uint16", "uint16", "uint256"];
const ESCROW = "contracts/PlexusEscrowV2.sol:PlexusEscrowV2";
const TOKEN = "contracts/MockUSDT.sol:MockUSDT";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ALREADY = /already verified|already been verified|perfect match|full match|partial match/i;

function escrowArgs(info) {
  return [info.token, info.owner, info.operator, info.treasury, info.feeBps, info.referrerBps, info.cashbackBps, info.minWithdrawal];
}

async function writeBundle(info) {
  const dir = path.join(__dirname, "..", "..", "deployments", "verify", info.network);
  fs.mkdirSync(dir, { recursive: true });
  const build = await artifacts.getBuildInfo(ESCROW);
  if (!build) throw new Error("No build info: run `npx hardhat compile` first");
  fs.writeFileSync(path.join(dir, "standard-input.json"), JSON.stringify(build.input));
  const args = ethers.AbiCoder.defaultAbiCoder().encode(CONSTRUCTOR_TYPES, escrowArgs(info)).slice(2);
  fs.writeFileSync(path.join(dir, "escrow-constructor-args.txt"), args);
  const scan = SUPPORTED[info.network]?.scan || "https://bscscan.com";
  const lines = [
    `BscScan manual verification (${info.network})`,
    ``,
    `Compiler:   v${build.solcLongVersion}`,
    `License:    MIT`,
    `Optimizer:  enabled, 200 runs (taken from standard-input.json)`,
    ``,
    `1. PlexusEscrowV2  ${info.escrow}`,
    `   ${scan}/verifyContract?a=${info.escrow}`,
    `   Compiler type: Solidity (Standard-Json-Input)`,
    `   Upload standard-input.json, contract name: ${ESCROW}`,
    `   Constructor arguments (ABI-encoded): contents of escrow-constructor-args.txt`,
  ];
  if (info.mockDeployed) {
    lines.push(
      ``,
      `2. MockUSDT  ${info.token}`,
      `   ${scan}/verifyContract?a=${info.token}`,
      `   Same compiler and standard-input.json, contract name: ${TOKEN}`,
      `   Constructor arguments: none`
    );
  }
  fs.writeFileSync(path.join(dir, "INSTRUCTIONS.txt"), lines.join("\n") + "\n");
  return { dir, compiler: build.solcLongVersion };
}

async function waitForConfirmations(info, blocks = 3, timeoutMs = 120000) {
  if (!info.deployTx) return;
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const rc = await ethers.provider.getTransactionReceipt(info.deployTx);
    if (rc && (await ethers.provider.getBlockNumber()) >= rc.blockNumber + blocks) return;
    await sleep(3000);
  }
}

async function etherscanSupportsChain(info) {
  const key = process.env.ETHERSCAN_API_KEY;
  if (!key) return { ok: false, why: "no ETHERSCAN_API_KEY" };
  try {
    const url = `https://api.etherscan.io/v2/api?chainid=${SUPPORTED[info.network].chainId}&module=account&action=balance&address=${info.deployer}&tag=latest&apikey=${key}`;
    const j = await (await fetch(url)).json();
    if (j.status === "1") return { ok: true };
    return { ok: false, why: String(j.result || j.message).slice(0, 90) };
  } catch (e) {
    return { ok: false, why: e.message };
  }
}

// Sourcify API v2 (v1 was removed, and hardhat-verify 2.1.x still calls v1, so we call v2 directly).
async function sourcifyVerify(chainId, address, contract) {
  const base = process.env.SOURCIFY_URL || "https://sourcify.dev/server";
  const build = await artifacts.getBuildInfo(contract);
  if (!build) throw new Error("No build info: run `npx hardhat compile` first");
  const res = await fetch(`${base}/v2/verify/${chainId}/${address}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ stdJsonInput: build.input, compilerVersion: build.solcLongVersion, contractIdentifier: contract }),
  });
  const body = await res.json().catch(() => ({}));
  if (res.status === 409) return "already verified";
  if (!res.ok) throw new Error(`Sourcify HTTP ${res.status}: ${body.message || JSON.stringify(body).slice(0, 160)}`);
  const id = body.verificationId;
  if (!id) throw new Error(`Sourcify gave no verification id: ${JSON.stringify(body).slice(0, 160)}`);
  for (let i = 0; i < 40; i++) {
    await sleep(3000);
    const j = await (await fetch(`${base}/v2/verify/${id}`)).json().catch(() => ({}));
    if (!j.isJobCompleted) continue;
    if (j.error) throw new Error(`Sourcify: ${j.error.message || j.error.customCode || JSON.stringify(j.error).slice(0, 160)}`);
    const match = j.contract?.match || j.contract?.runtimeMatch;
    if (match) return match;
    throw new Error(`Sourcify finished without a match: ${JSON.stringify(j).slice(0, 200)}`);
  }
  throw new Error("Sourcify verification timed out");
}

async function attempt(label, fn, { retries, retryMs }) {
  for (let i = 1; i <= retries; i++) {
    try {
      await fn();
      return true;
    } catch (e) {
      const msg = String(e.message || e);
      if (ALREADY.test(msg)) return true;
      if (i < retries) {
        console.log(`  ${label}: not ready (${msg.split("\n")[0].slice(0, 90)}), retrying in ${retryMs / 1000}s...`);
        await sleep(retryMs);
      } else {
        console.log(`  ${label}: failed: ${msg.split("\n")[0].slice(0, 160)}`);
      }
    }
  }
  return false;
}

async function verifyDeployment(info, { retries = 4, retryMs = 20000, bundleOnly = false } = {}) {
  const result = { bundle: null, sourcify: {}, etherscan: {} };
  try {
    if (!SUPPORTED[info.network] && !bundleOnly) {
      console.log(`(verification skipped: ${info.network} is not a public BSC network)`);
      return result;
    }
    console.log("\nVerification");
    const b = await writeBundle(info);
    result.bundle = b.dir;
    console.log(`  BscScan bundle written: ${b.dir}`);
    if (bundleOnly) return result;

    await waitForConfirmations(info);
    const targets = [["PlexusEscrowV2", info.escrow, ESCROW, escrowArgs(info)]];
    if (info.mockDeployed) targets.push(["MockUSDT", info.token, TOKEN, []]);

    for (const [name, address, contract] of targets) {
      result.sourcify[name] = await attempt(`Sourcify ${name}`, () => sourcifyVerify(SUPPORTED[info.network].chainId, address, contract), { retries, retryMs });
      if (result.sourcify[name]) console.log(`  Sourcify ${name}: verified  https://repo.sourcify.dev/${SUPPORTED[info.network].chainId}/${address}`);
    }

    const es = await etherscanSupportsChain(info);
    if (es.ok) {
      for (const [name, address, contract, constructorArgsParams] of targets) {
        result.etherscan[name] = await attempt(`BscScan ${name}`, () => run("verify:etherscan", { address, constructorArgsParams, contract, libraries: {} }), { retries, retryMs });
        if (result.etherscan[name]) console.log(`  BscScan ${name}: verified  ${SUPPORTED[info.network].scan}/address/${address}#code`);
      }
    } else {
      console.log(`  BscScan API skipped (${es.why}).`);
      console.log(`  To get the green check on BscScan, follow ${path.join(b.dir, "INSTRUCTIONS.txt")}`);
    }
  } catch (e) {
    console.log(`  verification step failed (deployment is fine): ${String(e.message || e).split("\n")[0]}`);
  }
  return result;
}

module.exports = { verifyDeployment };
