import assert from "node:assert/strict";
import { before, describe, it } from "node:test";

import { network } from "hardhat";

import RewardSystem from "../ignition/modules/RewardSystem.js";

/**
 * FEAT-006 T4 / AC-12: the on-chain half of UC-03 against the real Ignition module.
 * The CLI (FEAT-012/013) is not this feature.
 */
describe("allocation ledger: Ignition-deployed allocateBatch", () => {
  const TOKEN_NAME = "Reward Token";
  const TOKEN_SYMBOL = "RWD";
  const AMOUNT_A = 10n * 10n ** 18n;
  const AMOUNT_B = 25n * 10n ** 18n;

  let ownerAddress: `0x${string}`;
  let recipientA: `0x${string}`;
  let recipientB: `0x${string}`;
  let distributorAddress: `0x${string}`;

  let viem: Awaited<ReturnType<typeof network.create>>["viem"];

  before(async () => {
    const connection = await network.create({
      network: "hardhatOp",
      chainType: "op",
    });
    viem = connection.viem;

    const [deployer, owner, firstRecipient, secondRecipient] = await viem.getWalletClients();
    ownerAddress = owner.account.address;
    recipientA = firstRecipient.account.address;
    recipientB = secondRecipient.account.address;

    assert.notEqual(ownerAddress, deployer.account.address);

    const { distributor } = await connection.ignition.deploy(RewardSystem, {
      parameters: {
        RewardSystem: {
          tokenName: TOKEN_NAME,
          tokenSymbol: TOKEN_SYMBOL,
          owner: ownerAddress,
        },
      },
    });

    distributorAddress = distributor.address;
  });

  it("credits two recipients from allocateBatch issued by the configured owner", async () => {
    const publicClient = await viem.getPublicClient();
    const ownerWallet = await viem.getWalletClient(ownerAddress);

    const distributorAsOwner = await viem.getContractAt("RewardDistributor", distributorAddress, {
      client: { public: publicClient, wallet: ownerWallet },
    });

    await distributorAsOwner.write.allocateBatch([
      [recipientA, recipientB],
      [AMOUNT_A, AMOUNT_B],
    ]);

    assert.equal(await distributorAsOwner.read.unclaimed([recipientA]), AMOUNT_A);
    assert.equal(await distributorAsOwner.read.unclaimed([recipientB]), AMOUNT_B);
  });
});
