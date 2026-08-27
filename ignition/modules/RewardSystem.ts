import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/// Deploys the token, deploys the distributor bound to it, designates the distributor as
/// the token's authorized minter, and hands the token's ownership to the configured
/// owner — in one run (FR-DEPLOY-001).
///
/// The wiring call is the reason this is a single module rather than two. A deployment
/// whose `setMinter` never landed looks successful but makes every claim revert
/// (FR-CLAIM-011), which is why the post-deploy check in `scripts/check-deployment.ts`
/// is a required gate and not a nicety.
///
/// **Ordering note.** `setMinter` is `onlyOwner`, and FR-DEPLOY-008 forbids the owner
/// silently defaulting to the deploying key. Those two pull in opposite directions, so
/// the token is deployed owned by the deployer, wired, and *then* handed over with a
/// single-step `transferOwnership` (FR-OWN-002). The distributor needs no such dance —
/// nothing is called on it during deployment — so it is constructed already owned by the
/// configured owner. The post-deploy check asserts the final owner on both, which is
/// what closes this window.
///
/// Every parameter is **required, with no default**. That is deliberate: FR-DEPLOY-008
/// forbids defaulting the owner, and leaving the token name and symbol without defaults
/// means a deployment cannot accidentally ship a placeholder while TBD-1 is still open.
/// See `ignition/parameters.example.json`.
export default buildModule("RewardSystem", (m) => {
  const tokenName = m.getParameter<string>("tokenName");
  const tokenSymbol = m.getParameter<string>("tokenSymbol");
  const owner = m.getParameter<string>("owner");

  const deployer = m.getAccount(0);

  const token = m.contract("RewardToken", [tokenName, tokenSymbol, deployer]);
  const distributor = m.contract("RewardDistributor", [token, owner]);

  const wireMinter = m.call(token, "setMinter", [distributor]);
  m.call(token, "transferOwnership", [owner], { after: [wireMinter] });

  return { token, distributor };
});
