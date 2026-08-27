# Reward Token and Claim Distributor

An ERC-20 **reward token** on Base, paired with a **claim distributor** built on a
push-then-pull model. An off-chain process decides who earned what; the operator records
those amounts into the distributor's on-chain allocation map in batches; recipients then
claim what is recorded against their address and pay their own gas. Claimed tokens are
**minted at the moment of claim**, so no pre-funded pool is maintained and no supply
exists before it is owed.

There is no web UI, backend, or hosted API. Recipients interact through their own wallet
and the verified contract page — the contracts' public view functions and events _are_
the user interface.

**Current state: live on Base Sepolia.** Owner and
manager control, minting, pause, single and batch allocation, claim hardening, accounting
views, and ETH rejection are implemented and tested. See
[What exists today](#what-exists-today).

## Prerequisites

- Node.js 22.13 or later (built and tested on 22.18)
- npm

Nothing else. There is no database, no container, and no local service to run — all state
lives in contract storage, and development uses Hardhat's built-in simulated network.

## Getting started

```shell
npm ci
npm test
```

That compiles the contracts and runs both test layers. No configuration or network access
is needed for the test suite.

## Commands

| Command                                             | What it does                                                          |
| :-------------------------------------------------- | :-------------------------------------------------------------------- |
| `npm run build`                                     | Compile the contracts.                                                |
| `npm test`                                          | Run everything: Solidity unit tests and TypeScript integration tests. |
| `npm run test:solidity`                             | Solidity tests only (`test/*.t.sol`, in-EVM, forge-std cheatcodes).   |
| `npm run test:nodejs`                               | TypeScript tests only (`node:test` + viem).                           |
| `npm run coverage`                                  | Run the suite with coverage instrumentation.                          |
| `npm run coverage:check`                            | Enforce the coverage gate against `coverage/lcov.info`.               |
| `npm run lint`                                      | solhint over Solidity, plus a Prettier format check.                  |
| `npm run format`                                    | Rewrite files to the Prettier format.                                 |
| `npm run check-deployment -- --network baseSepolia` | Assert a live deployment is configured correctly.                     |

**Do not run the coverage command when measuring gas.** Coverage instrumentation enlarges
bytecode and disables the block gas limit, so any gas or batch-size measurement taken
under it is meaningless.

`check-deployment` is a **fresh-deploy** gate: it asserts `totalSupply == 0`. After a
real claim has minted supply, it will fail for that reason, which is correct. Do not
re-run it against the current Sepolia environment expecting green.

## Layout

```
contracts/         Production Solidity. This is the audit surface, and the coverage gate's scope.
                   RewardToken, RewardDistributor, and the shared Operable base.
test/              Solidity unit tests (*.t.sol) and TypeScript integration tests (*.ts).
ignition/modules/  Hardhat Ignition deployment modules — deploy and wiring in one run.
scripts/           Operator-side scripts: post-deploy check, coverage gate.
```

Solidity tests live in `test/`, not beside the contracts, so that `contracts/` contains
only production code — which makes the coverage gate's scope a simple path rule rather
than a filename convention.

## What exists today

**Implemented and accepted:**

- `RewardToken` — configurable name and symbol, 18 decimals, uncapped minting by owner,
  manager, or one designated minter; pause via OpenZeppelin `ERC20Pausable`; ETH rejected.
- `RewardDistributor` — single and batch allocation (additive, irrevocable), public
  `unclaimed` / `claimed` / `totalAllocated` / `totalClaimed` views, claim that zeroes
  the allocation then mints to the caller, independent pause, ETH rejected.
- `Operable` — one owner and one optional manager, inherited by both contracts;
  `renounceOwnership` permanently disabled.
- One-run Ignition deployment that wires the minter designation and hands ownership to
  the configured owner; a post-deploy configuration check; CI with lint, tests, and the
  coverage gate.

**Live on Base Sepolia** (Test402 Token / Test402).

| Contract          | Address                                                                                                                                |
| :---------------- | :------------------------------------------------------------------------------------------------------------------------------------- |
| RewardToken       | [`0x8D916a6AeD915Bea3F2a7BBBA9B527A4b4a32cD6`](https://base-sepolia.blockscout.com/address/0x8D916a6AeD915Bea3F2a7BBBA9B527A4b4a32cD6) |
| RewardDistributor | [`0xD9ACCFf56D151c50a984AF6d84acdCB9B9A095d4`](https://base-sepolia.blockscout.com/address/0xD9ACCFf56D151c50a984AF6d84acdCB9B9A095d4) |

Source is verified on Blockscout and Sourcify.

## Deploying

1. Fill in `.env` from [`.env.example`](.env.example), or better, put the key in the
   Hardhat keystore: `npx hardhat keystore set BASE_SEPOLIA_PRIVATE_KEY`.
2. Copy `ignition/parameters.example.json` to `ignition/parameters.json` and fill in the
   token name, symbol, and owner address. All three are required — there are no defaults,
   so a deployment cannot silently ship a placeholder name or leave the deploying key as
   permanent owner.
3. Deploy and verify:

```shell
npx hardhat ignition deploy ignition/modules/RewardSystem.ts \
  --network baseSepolia \
  --parameters ignition/parameters.json \
  --verify
```

4. Gate the result. **A deployment is not successful until this passes** — an unwired
   minter designation looks like a clean deploy but makes every claim revert:

```shell
npm run check-deployment -- --network baseSepolia
```

Base mainnet is reachable by the same process with `--network baseMainnet`.

Contracts are immutable. There is no on-chain rollback. To abandon a deployment, stop
using those addresses and redeploy.

## Trust

The token is uncapped and privileged keys can mint without limit.

Assets sent directly to either contract address are permanently unrecoverable by design.

## License

MIT. See [`LICENSE`](LICENSE).
