/**
 * Post-deployment configuration check (FR-DEPLOY-006).
 *
 * Reads the live chain and asserts that the deployment is actually configured the way it
 * was meant to be. This is a **gate, not a report**: a failing check must fail the
 * deployment (FR-DEPLOY-007), because the failure mode it catches is silent — a
 * deployment whose minter designation never landed looks perfectly successful while
 * making every claim revert (FR-CLAIM-011).
 *
 * Run it against a deployed network:
 *   npx hardhat run scripts/check-deployment.ts --network baseSepolia
 *
 * Expected values come from the same Ignition parameters file the deployment used, so
 * there is one source of truth rather than a hand-maintained second copy.
 *
 * Skeleton scope (FEAT-001) plus FEAT-002 and FEAT-005: asserts owner, manager
 * (unset until FEAT-011), minter designation, token binding, metadata, zero supply,
 * and that both contracts start unpaused.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";

import { network } from "hardhat";

import { runDeploymentChecks } from "./assert-deployment.ts";

const PARAMETERS_PATH = process.env.IGNITION_PARAMETERS ?? path.join("ignition", "parameters.json");
const MODULE_ID = "RewardSystem";

interface RewardSystemParameters {
  tokenName: string;
  tokenSymbol: string;
  owner: string;
}

function readParameters(): RewardSystemParameters {
  let raw: string;
  try {
    raw = readFileSync(PARAMETERS_PATH, "utf8");
  } catch {
    throw new Error(
      `Could not read Ignition parameters at ${PARAMETERS_PATH}. ` +
        `Copy ignition/parameters.example.json, fill it in, and set IGNITION_PARAMETERS if it lives elsewhere.`,
    );
  }

  const parsed = JSON.parse(raw) as Record<string, Partial<RewardSystemParameters>>;
  const params = parsed[MODULE_ID];
  if (params?.tokenName === undefined || params.tokenSymbol === undefined || params.owner === undefined) {
    throw new Error(`${PARAMETERS_PATH} must define ${MODULE_ID}.tokenName, .tokenSymbol and .owner`);
  }

  return params as RewardSystemParameters;
}

function readDeployedAddresses(chainId: number): Record<string, `0x${string}`> {
  const file = path.join("ignition", "deployments", `chain-${chainId}`, "deployed_addresses.json");
  try {
    return JSON.parse(readFileSync(file, "utf8")) as Record<string, `0x${string}`>;
  } catch {
    throw new Error(`No deployment artifact at ${file}. Deploy before checking.`);
  }
}

const expected = readParameters();

const connection = await network.getOrCreate();
const publicClient = await connection.viem.getPublicClient();
const chainId = await publicClient.getChainId();

const addresses = readDeployedAddresses(chainId);
const tokenAddress = addresses[`${MODULE_ID}#RewardToken`];
const distributorAddress = addresses[`${MODULE_ID}#RewardDistributor`];

assert.ok(tokenAddress, `deployment artifact is missing ${MODULE_ID}#RewardToken`);
assert.ok(distributorAddress, `deployment artifact is missing ${MODULE_ID}#RewardDistributor`);

const token = await connection.viem.getContractAt("RewardToken", tokenAddress);
const distributor = await connection.viem.getContractAt("RewardDistributor", distributorAddress);

console.log(`Checking deployment on chain ${chainId}`);
console.log(`  RewardToken       ${tokenAddress}`);
console.log(`  RewardDistributor ${distributorAddress}`);

const failed = await runDeploymentChecks({
  token,
  distributor,
  tokenAddress,
  distributorAddress,
  expected,
});

if (failed > 0) {
  console.error(`\n${failed} check(s) failed. Per FR-DEPLOY-007 this deployment is NOT successful.`);
  process.exitCode = 1;
} else {
  console.log("\nAll implemented checks passed.");
}
