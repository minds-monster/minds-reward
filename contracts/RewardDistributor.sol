// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Operable} from "./Operable.sol";
import {RewardToken} from "./RewardToken.sol";

/// @title RewardDistributor
/// @notice Records what each recipient is owed and lets them claim it themselves. Claimed
/// tokens are minted at claim time, so this contract never holds a balance.
/// @dev Access control is `Operable` (FEAT-002). Allocation recording (single and
/// batch) is complete (FEAT-006). Claim rules are FEAT-008. Accounting views
/// (`unclaimed`, `claimed`, `totalAllocated`, `totalClaimed`) are FEAT-007. Pause is
/// FEAT-005: independent of the token; `whenNotPaused` on allocate, allocateBatch, and
/// claim. Pause does not mutate allocations or claimed totals. ETH sent here is
/// rejected (FR-RESC-002); there is no rescue path for tokens held at this address
/// (FR-RESC-001). Claims mint and do not draw from a contract balance (FR-RESC-003).
contract RewardDistributor is Operable, Pausable {
    /// @notice The token this distributor mints. Bound once at construction and never
    /// changeable, so the distributor can never be re-pointed (FR-DEPLOY-002).
    RewardToken public immutable token;

    /// @notice The amount each address is owed and has not yet claimed (FR-ALLOC-013).
    /// @dev A single public mapping read is deliberately the recipient's whole interface:
    /// it satisfies NFR-USE-001 with no project-provided tooling.
    mapping(address recipient => uint256 amount) public unclaimed;

    /// @notice Lifetime amount each address has successfully claimed (FR-CLAIM-008,
    /// FR-ALLOC-015).
    mapping(address recipient => uint256 amount) public claimed;

    /// @notice Sum of every successful claim (FR-CLAIM-008, FR-ALLOC-014).
    uint256 public totalClaimed;

    /// @notice Sum of every amount that passed allocation recording (FR-ALLOC-014).
    /// @dev Incremented in `_allocate` after the zero-address / zero-amount guards.
    /// `totalAllocated - totalClaimed` is the outstanding reward liability.
    uint256 public totalAllocated;

    /// @notice Emitted once per recipient whose allocation is recorded (FR-ALLOC-012).
    /// @param recipient The address credited.
    /// @param amount The amount added by this call.
    /// @param unclaimedTotal The recipient's resulting unclaimed balance.
    event Allocated(address indexed recipient, uint256 amount, uint256 unclaimedTotal);

    /// @notice Emitted on every successful claim (FR-CLAIM-009).
    event Claimed(address indexed recipient, uint256 amount);

    /// @notice Thrown when the distributor would be bound to the zero address.
    error TokenAddressZero();

    /// @notice Thrown when an allocation targets the zero address, which could never claim.
    error AllocationToZeroAddress();

    /// @notice Thrown when an allocation records a zero amount (FR-ALLOC-008).
    error AllocationAmountZero();

    /// @notice Thrown when `allocateBatch` is called with two empty lists (FR-ALLOC-006).
    error EmptyBatch();

    /// @notice Thrown when `allocateBatch` is given address and amount lists of different lengths.
    error AllocationLengthMismatch(uint256 recipientsLength, uint256 amountsLength);

    /// @notice Thrown when an address with nothing owed tries to claim.
    error NothingToClaim(address caller);

    /// @notice Thrown when ETH is sent to this contract (FR-RESC-002).
    error EtherRejected();

    /// @param token_ The RewardToken this distributor mints (FR-DEPLOY-002).
    /// @param initialOwner The account holding privileged control from deployment (FR-OWN-001).
    constructor(address token_, address initialOwner) Operable(initialOwner) {
        if (token_ == address(0)) {
            revert TokenAddressZero();
        }
        token = RewardToken(payable(token_));
    }

    /// @notice Records a reward allocation for one recipient.
    /// @dev Additive, never a replacement (FR-ALLOC-002), and irreversible — no function
    /// exists anywhere to reduce or cancel it (FR-ALLOC-010). Callable by the owner or
    /// the designated manager (FR-OWN-006). Zero amount is rejected (FR-ALLOC-008).
    /// @param recipient The address to credit.
    /// @param amount The amount to add, in the token's smallest unit.
    function allocate(address recipient, uint256 amount) external onlyOperator whenNotPaused {
        _allocate(recipient, amount);
    }

    /// @notice Records allocations for many recipients in one call (FR-ALLOC-003).
    /// @dev All-or-nothing (FR-ALLOC-004). Duplicate addresses accumulate (FR-ALLOC-009).
    /// One `Allocated` event is emitted per list entry, including duplicates (FR-ALLOC-012).
    /// @param recipients The addresses to credit, in order.
    /// @param amounts The amounts to add, parallel to `recipients`.
    function allocateBatch(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOperator whenNotPaused {
        uint256 recipientsLength = recipients.length;
        uint256 amountsLength = amounts.length;
        if (recipientsLength != amountsLength) {
            revert AllocationLengthMismatch(recipientsLength, amountsLength);
        }
        if (recipientsLength == 0) {
            revert EmptyBatch();
        }
        for (uint256 i = 0; i < recipientsLength; ++i) {
            _allocate(recipients[i], amounts[i]);
        }
    }

    /// @notice Claims the caller's entire unclaimed allocation, minting it to them.
    /// @dev All-or-nothing, caller-only, no destination (FR-CLAIM-002, FR-CLAIM-005,
    /// FR-EXT-003). Unclaimed is zeroed and claimed totals updated *before* the external
    /// mint (FR-CLAIM-004, FR-CLAIM-008). A mint revert rolls the whole call back — there
    /// is no try/catch (FR-CLAIM-011). The only callee is the immutable bound token
    /// (FR-CLAIM-013).
    function claim() external whenNotPaused {
        uint256 amount = unclaimed[msg.sender];
        if (amount == 0) {
            revert NothingToClaim(msg.sender);
        }
        unclaimed[msg.sender] = 0;
        claimed[msg.sender] += amount;
        totalClaimed += amount;
        emit Claimed(msg.sender, amount);
        token.mint(msg.sender, amount);
    }

    /// @dev Shared single-entry rules so `allocate` and `allocateBatch` cannot drift.
    function _allocate(address recipient, uint256 amount) internal {
        if (recipient == address(0)) {
            revert AllocationToZeroAddress();
        }
        if (amount == 0) {
            revert AllocationAmountZero();
        }
        uint256 newTotal = unclaimed[recipient] + amount;
        unclaimed[recipient] = newTotal;
        totalAllocated += amount;
        emit Allocated(recipient, amount, newTotal);
    }

    /// @notice Freezes claims and allocation writes. Views remain available; recorded
    ///         allocations are left intact.
    /// @dev Callable by the owner or the designated manager (FR-OWN-006, FR-PAUSE-001).
    function pause() external onlyOperator {
        _pause();
    }

    /// @notice Lifts the freeze. Claims and allocation writes resume with prior state.
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
