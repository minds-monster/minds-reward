/**
 * Shared post-deploy assertions (FR-DEPLOY-006, FR-DEPLOY-007).
 *
 * The Hardhat runner in `check-deployment.ts` and the local mismatch test both
 * call `runDeploymentChecks` so a silent wiring failure cannot look green.
 */
import assert from "node:assert/strict";
import { zeroAddress } from "viem";

export const PENDING_DEPLOYMENT_ASSERTIONS: readonly string[] = [];

export interface DeploymentExpectations {
  tokenName: string;
  tokenSymbol: string;
  owner: string;
}

interface TokenViews {
  read: {
    name: () => Promise<string>;
    symbol: () => Promise<string>;
    decimals: () => Promise<number>;
    owner: () => Promise<string>;
    minter: () => Promise<string>;
    manager: () => Promise<string>;
    totalSupply: () => Promise<bigint>;
    paused: () => Promise<boolean>;
  };
}

interface DistributorViews {
  read: {
    owner: () => Promise<string>;
    manager: () => Promise<string>;
    token: () => Promise<string>;
    paused: () => Promise<boolean>;
  };
}

export interface DeploymentCheckLog {
  info: (message: string) => void;
  error: (message: string) => void;
}

const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();

/**
 * Runs the post-deploy assertions implemented so far. Returns the number of failed
 * checks. Does not throw on assertion failure — the caller treats a non-zero count as
 * FR-DEPLOY-007 failure.
 */
export async function runDeploymentChecks(input: {
  token: TokenViews;
  distributor: DistributorViews;
  tokenAddress: string;
  distributorAddress: string;
  expected: DeploymentExpectations;
  log?: DeploymentCheckLog;
}): Promise<number> {
  const log = input.log ?? { info: console.log, error: console.error };
  const { token, distributor, tokenAddress, distributorAddress, expected } = input;

  const checks: Array<[string, () => Promise<void>]> = [
    [
      "token metadata matches the deployment parameters (FR-DEPLOY-006)",
      async () => {
        assert.equal(await token.read.name(), expected.tokenName);
        assert.equal(await token.read.symbol(), expected.tokenSymbol);
        assert.equal(await token.read.decimals(), 18);
      },
    ],
    [
      "token owner is the configured owner, not the deployer (FR-DEPLOY-008)",
      async () => {
        assert.ok(same(await token.read.owner(), expected.owner));
      },
    ],
    [
      "distributor owner is the configured owner (FR-DEPLOY-008)",
      async () => {
        assert.ok(same(await distributor.read.owner(), expected.owner));
      },
    ],
    [
      "distributor is the token's authorized minter (FR-DEPLOY-001, FR-CLAIM-011)",
      async () => {
        assert.ok(same(await token.read.minter(), distributorAddress));
      },
    ],
    [
      "distributor is bound to the deployed token (FR-DEPLOY-002)",
      async () => {
        assert.ok(same(await distributor.read.token(), tokenAddress));
      },
    ],
    [
      "total supply is zero — nothing minted yet (FR-DEPLOY-006)",
      async () => {
        assert.equal(await token.read.totalSupply(), 0n);
      },
    ],
    [
      "token manager is unset — designation at deploy is FEAT-011 (FR-DEPLOY-006)",
      async () => {
        assert.ok(same(await token.read.manager(), zeroAddress));
      },
    ],
    [
      "distributor manager is unset — designation at deploy is FEAT-011 (FR-DEPLOY-006)",
      async () => {
        assert.ok(same(await distributor.read.manager(), zeroAddress));
      },
    ],
    [
      "both contracts start unpaused (FR-PAUSE-003, FR-DEPLOY-006)",
      async () => {
        assert.equal(await token.read.paused(), false);
        assert.equal(await distributor.read.paused(), false);
      },
    ],
  ];

  let failed = 0;
  for (const [description, check] of checks) {
    try {
      await check();
      log.info(`  PASS  ${description}`);
    } catch (error) {
      failed += 1;
      log.error(`  FAIL  ${description}`);
      log.error(`        ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  if (PENDING_DEPLOYMENT_ASSERTIONS.length > 0) {
    log.info("\nAssertions not yet implemented (the contracts do not carry this state yet):");
    for (const pending of PENDING_DEPLOYMENT_ASSERTIONS) {
      log.info(`  - ${pending}`);
    }
  }

  return failed;
}
