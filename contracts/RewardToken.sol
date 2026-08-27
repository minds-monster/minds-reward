// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {Operable} from "./Operable.sol";

/// @title RewardToken
/// @notice An ERC-20 reward token whose supply is created on demand by the owner or by a
/// single designated minter contract.
/// @dev Access control is `Operable` (FEAT-002). Minting rules are FEAT-004: owner,
/// manager, or the designated minter may mint; there is no cap and no burn. Pause is
/// FEAT-005: `ERC20Pausable` freezes transfers and minting via `_update`; `approve` stays
/// available. Accounting and metadata are inherited from OpenZeppelin unmodified
/// (NFR-SEC-001). ETH sent here is rejected (FR-RESC-002); there is no rescue path
/// for tokens held at this address (FR-RESC-001).
contract RewardToken is ERC20Pausable, Operable {
    /// @notice The one address, besides the owner, permitted to create new supply.
    /// @dev Intended for the RewardDistributor, so claims can mint rather than draw from
    /// a pre-funded pool (FR-SUP-003).
    address public minter;

    /// @notice Emitted whenever the designated minter changes (FR-SUP-009).
    /// @param previousMinter The designation being replaced; the zero address if none.
    /// @param newMinter The new designation; the zero address when the designation is cleared.
    event MinterChanged(address indexed previousMinter, address indexed newMinter);

    /// @notice Thrown when an address that is neither the owner, the manager, nor the
    ///         minter tries to mint.
    error NotAuthorizedToMint(address caller);

    /// @notice Thrown when a mint targets the zero address.
    error MintToZeroAddress();

    /// @notice Thrown when ETH is sent to this contract (FR-RESC-002).
    error EtherRejected();

    /// @param name_ The human-readable token name (FR-TOK-001).
    /// @param symbol_ The short token symbol (FR-TOK-002).
    /// @param initialOwner The account holding privileged control from deployment (FR-OWN-001).
    constructor(
        string memory name_,
        string memory symbol_,
        address initialOwner
    ) ERC20(name_, symbol_) Operable(initialOwner) {}

    /// @notice Sets, replaces, or clears the designated minter.
    /// @dev Passing the zero address revokes minting authority, which makes every claim
    /// revert until a new designation is set (FR-SUP-005).
    /// @param newMinter The address to designate, or the zero address to clear.
    function setMinter(address newMinter) external onlyOwner {
        emit MinterChanged(minter, newMinter);
        minter = newMinter;
    }

    /// @notice Creates new tokens and assigns them to an address.
    /// @dev Callable by the owner (FR-SUP-001), the designated manager (FR-OWN-006), or
    /// the designated minter (FR-SUP-004); every other caller reverts (FR-SUP-006). Emits
    /// `Transfer` from the zero address via OpenZeppelin's `_mint` (FR-ERC-007).
    /// @param to The address to credit.
    /// @param amount The amount to create, in the token's smallest unit.
    function mint(address to, uint256 amount) external {
        if (!_isOperator(msg.sender) && msg.sender != minter) {
            revert NotAuthorizedToMint(msg.sender);
        }
        if (to == address(0)) {
            revert MintToZeroAddress();
        }
        _mint(to, amount);
    }

    /// @notice Freezes transfers and minting. Approvals and views remain available.
    /// @dev Callable by the owner or the designated manager (FR-OWN-006, FR-PAUSE-001).
    function pause() external onlyOperator {
        _pause();
    }

    /// @notice Lifts the freeze. Functionality returns exactly as it was before pause.
    /// @dev Callable by the owner or the designated manager (FR-OWN-006, FR-PAUSE-002).
    function unpause() external onlyOperator {
        _unpause();
    }

    /// @notice Rejects plain ETH transfers. This contract does not hold or forward ETH.
    receive() external payable {
        revert EtherRejected();
    }

    /// @notice Rejects ETH sent with calldata, including unknown selectors.
    fallback() external payable {
        revert EtherRejected();
    }
}
