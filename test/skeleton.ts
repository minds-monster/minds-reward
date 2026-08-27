import assert from "node:assert/strict";
import { before, describe, it } from "node:test";

import { network } from "hardhat";

import RewardSystem from "../ignition/modules/RewardSystem.js";

/**
 * The walking skeleton's end-to-end test — the local half of FEAT-001's done-when
 * condition, encoded.
 *
 * It deliberately deploys through the **real Ignition module** rather than constructing
 * the contracts by hand, because the wiring step is the thing that fails silently: a
 * deployment whose `setMinter` never landed looks successful and makes every claim revert
 * (FR-CLAIM-011, architecture §6). A hand-rolled deploy in this test would prove the
 * contracts work while leaving the actual deployment path untested.
 *
 * The owner is deliberately an account *other* than the deployer, so the test also
 * exercises FR-DEPLOY-008 (owner comes from configuration) and the module's
 * wire-then-hand-over ordering.
 *
 * The deployed half of the done-when — a real Base Sepolia deployment, verified on
 * BaseScan, with a real claim — remains pending; it is an explicit human action, not
 * something scaffolding performs.
 */
describe("walking skeleton: deploy, wire, allocate, claim", () => {
  const TOKEN_NAME = "Reward Token";
  const TOKEN_SYMBOL = "RWD";
  const ALLOCATION = 42n * 10n ** 18n;

  let ownerAddress: `0x${string}`;
  let recipientAddress: `0x${string}`;
  let tokenAddress: `0x${string}`;
  let distributorAddress: `0x${string}`;

  let viem: Awaited<ReturnType<typeof network.create>>["viem"];

  before(async () => {
    const connection = await network.create({
      network: "hardhatOp",
      chainType: "op",
    });
    viem = connection.viem;

    const [deployer, owner, recipient] = await viem.getWalletClients();
    ownerAddress = owner.account.address;
    recipientAddress = recipient.account.address;

    assert.notEqual(
      ownerAddress,
      deployer.account.address,
      "the owner must differ from the deployer for this test to mean anything",
    );

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

  it("deploys the token with the configured metadata and no supply", async () => {
    const token = await viem.getContractAt("RewardToken", tokenAddress);

    assert.equal(await token.read.name(), TOKEN_NAME);
    assert.equal(await token.read.symbol(), TOKEN_SYMBOL);
    assert.equal(await token.read.decimals(), 18);
    assert.equal(await token.read.totalSupply(), 0n, "no supply should exist before a claim");
  });

  it("hands both contracts to the configured owner, not the deployer", async () => {
    const token = await viem.getContractAt("RewardToken", tokenAddress);
    const distributor = await viem.getContractAt("RewardDistributor", distributorAddress);

    assert.equal(
      (await token.read.owner()).toLowerCase(),
      ownerAddress.toLowerCase(),
      "FR-DEPLOY-008: the token owner comes from configuration",
    );
    assert.equal(
      (await distributor.read.owner()).toLowerCase(),
      ownerAddress.toLowerCase(),
      "FR-DEPLOY-008: the distributor owner comes from configuration",
    );
  });

  it("wires the distributor as the token's authorized minter", async () => {
    const token = await viem.getContractAt("RewardToken", tokenAddress);
    const distributor = await viem.getContractAt("RewardDistributor", distributorAddress);

    assert.equal(
      (await token.read.minter()).toLowerCase(),
      distributorAddress.toLowerCase(),
      "FR-DEPLOY-001: an unwired deployment makes every claim revert",
    );
    assert.equal(
      (await distributor.read.token()).toLowerCase(),
      tokenAddress.toLowerCase(),
      "FR-DEPLOY-002: the distributor is bound to one token",
    );
  });

  it("records an allocation and pays it out as a claim that mints new supply", async () => {
    const publicClient = await viem.getPublicClient();
    const ownerWallet = await viem.getWalletClient(ownerAddress);
    const recipientWallet = await viem.getWalletClient(recipientAddress);

    const distributorAsOwner = await viem.getContractAt("RewardDistributor", distributorAddress, {
      client: { public: publicClient, wallet: ownerWallet },
    });
    const distributorAsRecipient = await viem.getContractAt("RewardDistributor", distributorAddress, {
      client: { public: publicClient, wallet: recipientWallet },
    });
    const token = await viem.getContractAt("RewardToken", tokenAddress);

    await distributorAsOwner.write.allocate([recipientAddress, ALLOCATION]);

    assert.equal(
      await distributorAsRecipient.read.unclaimed([recipientAddress]),
      ALLOCATION,
      "NFR-USE-001: the recipient reads what they are owed in one call",
    );

    await distributorAsRecipient.write.claim();

    assert.equal(
      await token.read.balanceOf([recipientAddress]),
      ALLOCATION,
      "the claim should mint to the claimant",
    );
    assert.equal(
      await distributorAsRecipient.read.unclaimed([recipientAddress]),
      0n,
      "the claim should zero the allocation",
    );
    assert.equal(
      await token.read.totalSupply(),
      ALLOCATION,
      "mint-on-claim creates the supply at claim time",
    );
    assert.equal(
      await distributorAsRecipient.read.claimed([recipientAddress]),
      ALLOCATION,
      "FR-CLAIM-008: per-address claimed totals the first payout",
    );
    assert.equal(
      await distributorAsRecipient.read.totalClaimed(),
      ALLOCATION,
      "FR-CLAIM-008: system-wide claimed totals the first payout",
    );

    const secondAllocation = 17n * 10n ** 18n;
    await distributorAsOwner.write.allocate([recipientAddress, secondAllocation]);
    await distributorAsRecipient.write.claim();

    assert.equal(
      await distributorAsRecipient.read.unclaimed([recipientAddress]),
      0n,
      "FR-CLAIM-007: a further allocation is fully paid on the next claim",
    );
    assert.equal(
      await distributorAsRecipient.read.claimed([recipientAddress]),
      ALLOCATION + secondAllocation,
    );
    assert.equal(await distributorAsRecipient.read.totalClaimed(), ALLOCATION + secondAllocation);
    assert.equal(await token.read.balanceOf([recipientAddress]), ALLOCATION + secondAllocation);
    assert.equal(await token.read.totalSupply(), ALLOCATION + secondAllocation);
  });
});
