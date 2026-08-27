import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";

/**
 * FEAT-003 AC-15 / AC-3: the token exposes the EIP-20 members wallets and integrators
 * need, and has no metadata setters (FR-EXT-001, FR-EXT-005, FR-TOK-005).
 */
type AbiItem = {
  type?: string;
  name?: string;
};

function missingFunctions(abi: readonly AbiItem[], required: Set<string>): string[] {
  return [...required]
    .filter((name) => !abi.some((item) => item.type === "function" && item.name === name))
    .sort();
}

function presentFunctions(abi: readonly AbiItem[], names: readonly string[]): string[] {
  return names.filter((name) => abi.some((item) => item.type === "function" && item.name === name)).sort();
}

describe("ERC-20 ABI (FR-EXT-001, FR-EXT-005, FR-TOK-005)", () => {
  it("RewardToken ABI includes EIP-20 members and no metadata setters", async () => {
    const { viem } = await network.create({
      network: "hardhatOp",
      chainType: "op",
    });
    const [wallet] = await viem.getWalletClients();
    const token = await viem.deployContract("RewardToken", ["Reward Token", "RWD", wallet.account.address]);

    const required = new Set([
      "name",
      "symbol",
      "decimals",
      "totalSupply",
      "balanceOf",
      "allowance",
      "transfer",
      "approve",
      "transferFrom",
    ]);
    const metadataSetters = ["setName", "setSymbol", "setDecimals"];

    assert.deepEqual(missingFunctions(token.abi, required), []);
    assert.deepEqual(presentFunctions(token.abi, metadataSetters), [], "FR-TOK-005: no metadata setters");
  });
});
