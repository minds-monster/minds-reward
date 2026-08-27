import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";

/**
 * NFR-SEC-002 / AC-16: a reviewer can enumerate the privileged surface from the
 * contract interface alone. This test is that enumeration, encoded.
 */
type AbiItem = {
  type?: string;
  name?: string;
  stateMutability?: string;
  inputs?: readonly unknown[];
};

function unexpectedStateChanging(abi: readonly AbiItem[], allowed: Set<string>): string[] {
  const extra: string[] = [];
  for (const item of abi) {
    if (item.type !== "function" || item.name === undefined) {
      continue;
    }
    if (allowed.has(item.name)) {
      continue;
    }
    if (item.stateMutability === "view" || item.stateMutability === "pure") {
      continue;
    }
    extra.push(item.name);
  }
  return extra.sort();
}

function missingFunctions(abi: readonly AbiItem[], required: Set<string>): string[] {
  return [...required]
    .filter((name) => !abi.some((item) => item.type === "function" && item.name === name))
    .sort();
}

describe("privileged surface (NFR-SEC-002, AC-16)", () => {
  it("RewardToken ABI exposes exactly the designed privileged set", async () => {
    const { viem } = await network.create({
      network: "hardhatOp",
      chainType: "op",
    });
    const [wallet] = await viem.getWalletClients();
    const token = await viem.deployContract("RewardToken", ["Reward Token", "RWD", wallet.account.address]);

    const privileged = new Set([
      "setManager",
      "transferOwnership",
      "renounceOwnership",
      "setMinter",
      "mint",
      "pause",
      "unpause",
    ]);
    const unprivilegedState = new Set(["transfer", "approve", "transferFrom"]);
    const allowed = new Set([...privileged, ...unprivilegedState]);
    const forbidden = [
      "burn",
      "burnFrom",
      "cap",
      "maxSupply",
      "rescue",
      "rescueTokens",
      "rescueETH",
      "withdraw",
      "withdrawToken",
      "withdrawERC20",
      "recover",
      "recoverTokens",
      "recoverERC20",
      "sweep",
      "sweepTokens",
      "emergencyWithdraw",
      "skim",
    ];

    assert.deepEqual(missingFunctions(token.abi, privileged), []);
    assert.deepEqual(unexpectedStateChanging(token.abi, allowed), []);
    assert.deepEqual(
      forbidden.filter((name) => token.abi.some((item) => item.type === "function" && item.name === name)),
      [],
      "FR-SUP-002 / FR-SUP-008 / FR-RESC-001: no cap, no burn, and no rescue on the token ABI",
    );
  });

  it("RewardDistributor ABI exposes exactly the designed privileged set", async () => {
    const { viem } = await network.create({
      network: "hardhatOp",
      chainType: "op",
    });
    const [wallet] = await viem.getWalletClients();
    const token = await viem.deployContract("RewardToken", ["Reward Token", "RWD", wallet.account.address]);
    const distributor = await viem.deployContract("RewardDistributor", [
      token.address,
      wallet.account.address,
    ]);

    const privileged = new Set([
      "setManager",
      "transferOwnership",
      "renounceOwnership",
      "allocate",
      "allocateBatch",
      "pause",
      "unpause",
    ]);
    const unprivilegedState = new Set(["claim"]);
    const allowed = new Set([...privileged, ...unprivilegedState]);
    const forbidden = [
      "decreaseAllocation",
      "reduceAllocation",
      "cancelAllocation",
      "revokeAllocation",
      "expireAllocation",
      "expire",
      "deadline",
      "setExpiry",
      "setUnclaimed",
      "claimTo",
      "claimFor",
      "claimFrom",
      "rescue",
      "rescueTokens",
      "rescueETH",
      "withdraw",
      "withdrawToken",
      "withdrawERC20",
      "recover",
      "recoverTokens",
      "recoverERC20",
      "sweep",
      "sweepTokens",
      "emergencyWithdraw",
      "skim",
    ];

    const claimFns = distributor.abi.filter((item) => item.type === "function" && item.name === "claim");
    assert.equal(claimFns.length, 1, "FR-EXT-003: exactly one claim entry point");
    assert.deepEqual(
      claimFns[0]?.inputs ?? [],
      [],
      "FR-CLAIM-002 / FR-EXT-003: claim() takes no amount or destination",
    );

    assert.deepEqual(missingFunctions(distributor.abi, privileged), []);
    assert.deepEqual(unexpectedStateChanging(distributor.abi, allowed), []);
    assert.deepEqual(
      forbidden.filter((name) =>
        distributor.abi.some((item) => item.type === "function" && item.name === name),
      ),
      [],
      "FR-ALLOC-010 / FR-CLAIM-005 / FR-CLAIM-013 / FR-RESC-001: no reduce path, no alternate claim destination, and no rescue",
    );
  });
});
