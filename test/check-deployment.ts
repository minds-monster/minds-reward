import assert from "node:assert/strict";
import { before, describe, it } from "node:test";

import { network } from "hardhat";
import { zeroAddress } from "viem";

import { runDeploymentChecks, PENDING_DEPLOYMENT_ASSERTIONS } from "../scripts/assert-deployment.ts";
import RewardSystem from "../ignition/modules/RewardSystem.js";

/**
 * Local half of FR-DEPLOY-007: a metadata mismatch must not look like a successful
 * deployment. Uses the real Ignition module so the checker sees the same wiring the
 * live script does.
 */
describe("post-deploy checker (FR-DEPLOY-006, FR-DEPLOY-007)", () => {
  const TOKEN_NAME = "Reward Token";
  const TOKEN_SYMBOL = "RWD";

  let ownerAddress: `0x${string}`;
  let tokenAddress: `0x${string}`;
  let distributorAddress: `0x${string}`;
  let viem: Awaited<ReturnType<typeof network.create>>["viem"];

  before(async () => {
    const connection = await network.create({
      network: "hardhatOp",
      chainType: "op",
    });
    viem = connection.viem;

    const [deployer, owner] = await viem.getWalletClients();
    ownerAddress = owner.account.address;

    assert.notEqual(ownerAddress, deployer.account.address);

    const { token, distributor } = await connection.ignition.deploy(RewardSystem, {
      parameters: {
        RewardSystem: {
          tokenName: TOKEN_NAME,
          tokenSymbol: TOKEN_SYMBOL,
          owner: ownerAddress,
        },
      },
    });

    tokenAddress = token.address;
    distributorAddress = distributor.address;
  });

  it("passes against a correctly wired Ignition deployment", async () => {
    const token = await viem.getContractAt("RewardToken", tokenAddress);
    const distributor = await viem.getContractAt("RewardDistributor", distributorAddress);

    const failed = await runDeploymentChecks({
      token,
      distributor,
      tokenAddress,
      distributorAddress,
      expected: { tokenName: TOKEN_NAME, tokenSymbol: TOKEN_SYMBOL, owner: ownerAddress },
      log: { info: () => {}, error: () => {} },
    });

    assert.equal(failed, 0, "matching parameters should pass every implemented check");
  });

  it("exits as failed when token metadata does not match parameters", async () => {
    const token = await viem.getContractAt("RewardToken", tokenAddress);
    const distributor = await viem.getContractAt("RewardDistributor", distributorAddress);

    const errors: string[] = [];
    const failed = await runDeploymentChecks({
      token,
      distributor,
      tokenAddress,
      distributorAddress,
      expected: { tokenName: "WRONG NAME", tokenSymbol: TOKEN_SYMBOL, owner: ownerAddress },
      log: { info: () => {}, error: (message) => errors.push(message) },
    });

    assert.ok(failed > 0, "FR-DEPLOY-007: a mismatch must not be reported as success");
    assert.ok(
      errors.some((line) => line.includes("FAIL")),
      "the checker should report the failed assertion",
    );
  });

  it("asserts manager is unset and no longer lists it as pending", async () => {
    const token = await viem.getContractAt("RewardToken", tokenAddress);
    const distributor = await viem.getContractAt("RewardDistributor", distributorAddress);

    assert.equal(await token.read.manager(), zeroAddress);
    assert.equal(await distributor.read.manager(), zeroAddress);
    assert.ok(
      !PENDING_DEPLOYMENT_ASSERTIONS.some((line) => /manager|FEAT-002/i.test(line)),
      "FEAT-002 manager checks are implemented, not pending",
    );
    assert.equal(await token.read.paused(), false);
    assert.equal(await distributor.read.paused(), false);
    assert.equal(
      PENDING_DEPLOYMENT_ASSERTIONS.length,
      0,
      "FEAT-005 pause checks are implemented; the pending list is empty",
    );
  });

  it("exits as failed when the token is paused", async () => {
    const publicClient = await viem.getPublicClient();
    const ownerWallet = await viem.getWalletClient(ownerAddress);
    const token = await viem.getContractAt("RewardToken", tokenAddress, {
      client: { public: publicClient, wallet: ownerWallet },
    });
    const distributor = await viem.getContractAt("RewardDistributor", distributorAddress);

    await token.write.pause();

    const errors: string[] = [];
    const failed = await runDeploymentChecks({
      token,
      distributor,
      tokenAddress,
      distributorAddress,
      expected: { tokenName: TOKEN_NAME, tokenSymbol: TOKEN_SYMBOL, owner: ownerAddress },
      log: { info: () => {}, error: (message) => errors.push(message) },
    });

    assert.ok(failed > 0, "FR-DEPLOY-007: a paused token must not be reported as a successful deploy");
    assert.ok(
      errors.some((line) => line.includes("FAIL")),
      "the checker should report the failed pause assertion",
    );

    await token.write.unpause();
  });
});
