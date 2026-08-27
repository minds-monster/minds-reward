// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Operable
/// @notice Shared two-tier access control: one owner and one optional manager.
/// @dev Extends OpenZeppelin `Ownable` unmodified (ADR-003). Renouncing is disabled
///      (FR-OWN-004) so a contract cannot become ownerless. Both `RewardToken` and
///      `RewardDistributor` inherit this rather than `Ownable` directly.
abstract contract Operable is Ownable {
    /// @notice The one address, besides the owner, permitted to perform day-to-day
    ///         privileged operations (FR-OWN-005). The zero address means none.
    address public manager;

    /// @notice Emitted whenever the designated manager changes (FR-OWN-011).
    /// @param previousManager The designation being replaced; the zero address if none.
    /// @param newManager The new designation; the zero address when the designation is cleared.
    event ManagerChanged(address indexed previousManager, address indexed newManager);

    /// @notice Thrown when a caller that is neither the owner nor the manager attempts
    ///         an operator-gated action (FR-OWN-008).
    error NotOperator(address caller);

    /// @notice Thrown by `renounceOwnership`, which is permanently disabled (FR-OWN-004).
    error RenounceOwnershipDisabled();

    /// @param initialOwner The account holding non-delegable control from deployment (FR-OWN-001).
    constructor(address initialOwner) Ownable(initialOwner) {}

    /// @notice Restricts a function to the owner or the designated manager (FR-OWN-006).
    modifier onlyOperator() {
        if (!_isOperator(_msgSender())) {
            revert NotOperator(_msgSender());
        }
        _;
    }

    /// @dev True when `account` is the owner or the current manager.
    function _isOperator(address account) internal view returns (bool) {
        return account == owner() || account == manager;
    }

    /// @notice Sets, replaces, or clears the designated manager (FR-OWN-005, FR-OWN-007).
    /// @dev Passing the zero address revokes the manager. Setting the current value still
    ///      succeeds and emits (design D3).
    /// @param newManager The address to designate, or the zero address to clear.
    function setManager(address newManager) external onlyOwner {
        emit ManagerChanged(manager, newManager);
        manager = newManager;
    }

    /// @notice Permanently disabled. An ownerless contract could never mint, unpause, or
    ///         record allocations again (FR-OWN-004).
    /// @dev Remains in the ABI as a reverting function (ADR-003). Always reverts, including
    ///      for the owner and for strangers (design D5).
    function renounceOwnership() public pure override {
        revert RenounceOwnershipDisabled();
    }
}
