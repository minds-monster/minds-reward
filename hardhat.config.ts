import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import hardhatIgnitionViemPlugin from "@nomicfoundation/hardhat-ignition-viem";
import { configVariable, defineConfig } from "hardhat/config";

// Base is an OP Stack chain, so every Base network is declared with chainType "op"
// and the local simulated network mirrors that (NFR-CMP-003: no chain-specific
// opcodes, but the simulated EVM should still match the target).
export default defineConfig({
  plugins: [hardhatToolboxViemPlugin, hardhatIgnitionViemPlugin],

  solidity: {
    // Pinned exactly, not a caret range. ADR-011 requires a single pinned compiler,
    // and architecture risk 6 notes the coverage instrumentation constrains which
    // version we may use — a bump is a tested change, not a silent one.
    profiles: {
      default: {
        version: "0.8.28",
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },

  networks: {
    // Local development and the whole test suite. No container, no external
    // dependency: this system has no store other than the chain itself.
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },

    baseSepolia: {
      type: "http",
      chainType: "op",
      chainId: 84532,
      url: configVariable("BASE_SEPOLIA_RPC_URL"),
      accounts: [configVariable("BASE_SEPOLIA_PRIVATE_KEY")],
    },

    // The eventual production target. Deploying here requires the mainnet gate in
    // docs/architecture.md §11 to be satisfied first, and a key that is never the
    // testnet key.
    baseMainnet: {
      type: "http",
      chainType: "op",
      chainId: 8453,
      url: configVariable("BASE_MAINNET_RPC_URL"),
      accounts: [configVariable("BASE_MAINNET_PRIVATE_KEY")],
    },
  },

  verify: {
    etherscan: {
      apiKey: configVariable("BASESCAN_API_KEY"),
    },
  },
});
