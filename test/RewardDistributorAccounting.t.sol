// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {RewardToken} from "../contracts/RewardToken.sol";
import {RewardDistributor} from "../contracts/RewardDistributor.sol";

/// @dev FEAT-007: accounting views — totalAllocated write-side (AC-3, AC-4) and
/// the explorer read matrix (AC-1, AC-2, AC-5..9).
contract RewardDistributorAccountingTest is Test {
    RewardToken internal token;
    RewardDistributor internal distributor;

    address internal owner;
    address internal recipient;
    address internal recipientB;
    address internal stranger;

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");
        recipientB = makeAddr("recipientB");
        stranger = makeAddr("stranger");

        token = new RewardToken("Reward Token", "RWD", owner);
        distributor = new RewardDistributor(address(token), owner);

        vm.prank(owner);
        token.setMinter(address(distributor));
    }

    function test_AllocateIncreasesTotalAllocatedByAmount() public {
        assertEq(distributor.totalAllocated(), 0);

        vm.prank(owner);
        distributor.allocate(recipient, 3 ether);

        assertEq(distributor.totalAllocated(), 3 ether);

        vm.prank(owner);
        distributor.allocate(recipient, 2 ether);

        assertEq(distributor.totalAllocated(), 5 ether);
        assertEq(distributor.unclaimed(recipient), 5 ether);
    }

    function test_AllocateBatchIncreasesTotalAllocatedBySumIncludingDuplicates() public {
        address[] memory recipients = new address[](3);
        recipients[0] = recipient;
        recipients[1] = recipientB;
        recipients[2] = recipient;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 4 ether;
        amounts[2] = 2 ether;

        vm.prank(owner);
        distributor.allocateBatch(recipients, amounts);

        assertEq(distributor.totalAllocated(), 7 ether);
        assertEq(distributor.unclaimed(recipient), 3 ether);
        assertEq(distributor.unclaimed(recipientB), 4 ether);
    }

    function test_AllocateToZeroAddressLeavesTotalAllocatedUnchanged() public {
        vm.prank(owner);
        distributor.allocate(recipient, 1 ether);

        vm.expectRevert(RewardDistributor.AllocationToZeroAddress.selector);
        vm.prank(owner);
        distributor.allocate(address(0), 5 ether);

        assertEq(distributor.totalAllocated(), 1 ether);
    }

    function test_AllocateZeroAmountLeavesTotalAllocatedUnchanged() public {
        vm.prank(owner);
        distributor.allocate(recipient, 1 ether);

        vm.expectRevert(RewardDistributor.AllocationAmountZero.selector);
        vm.prank(owner);
        distributor.allocate(recipient, 0);

        assertEq(distributor.totalAllocated(), 1 ether);
    }

    function test_AllocateBatchLengthMismatchLeavesTotalAllocatedUnchanged() public {
        vm.prank(owner);
        distributor.allocate(recipient, 1 ether);

        address[] memory recipients = new address[](1);
        recipients[0] = recipient;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2 ether;
        amounts[1] = 3 ether;

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.AllocationLengthMismatch.selector, 1, 2));
        vm.prank(owner);
        distributor.allocateBatch(recipients, amounts);

        assertEq(distributor.totalAllocated(), 1 ether);
    }

    function test_AllocateBatchEmptyListsLeaveTotalAllocatedUnchanged() public {
        vm.prank(owner);
        distributor.allocate(recipient, 1 ether);

        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert(RewardDistributor.EmptyBatch.selector);
        vm.prank(owner);
        distributor.allocateBatch(recipients, amounts);

        assertEq(distributor.totalAllocated(), 1 ether);
    }

    function test_AllocateBatchBadLastEntryRollsBackTotalAllocated() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient;
        recipients[1] = address(0);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 4 ether;
        amounts[1] = 1 ether;

        vm.expectRevert(RewardDistributor.AllocationToZeroAddress.selector);
        vm.prank(owner);
        distributor.allocateBatch(recipients, amounts);

        assertEq(distributor.totalAllocated(), 0);
        assertEq(distributor.unclaimed(recipient), 0);
    }

    function test_UnclaimedIsZeroThenAmountThenZeroAfterClaim() public {
        assertEq(distributor.unclaimed(recipient), 0);

        vm.prank(owner);
        distributor.allocate(recipient, 4 ether);

        assertEq(distributor.unclaimed(recipient), 4 ether);

        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 0);
    }

    function test_ClaimedAccumulatesAcrossAllocateClaimCycles() public {
        assertEq(distributor.claimed(recipient), 0);

        vm.prank(owner);
        distributor.allocate(recipient, 2 ether);
        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.claimed(recipient), 2 ether);

        vm.prank(owner);
        distributor.allocate(recipient, 5 ether);
        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.claimed(recipient), 7 ether);
        assertEq(distributor.totalClaimed(), 7 ether);
    }

    function test_NeverAllocatedVsFullyClaimedAreDistinguishable() public {
        vm.prank(owner);
        distributor.allocate(recipient, 3 ether);
        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(distributor.claimed(recipient), 3 ether);

        assertEq(distributor.unclaimed(stranger), 0);
        assertEq(distributor.claimed(stranger), 0);
    }

    function test_ViewsAnswerForTheAddressAskedNotTheCaller() public {
        vm.prank(owner);
        distributor.allocate(recipient, 6 ether);

        vm.prank(stranger);
        assertEq(distributor.unclaimed(recipient), 6 ether);
        vm.prank(stranger);
        assertEq(distributor.claimed(recipient), 0);
        vm.prank(stranger);
        assertEq(distributor.unclaimed(stranger), 0);
        vm.prank(stranger);
        assertEq(distributor.claimed(stranger), 0);

        vm.prank(recipient);
        distributor.claim();

        vm.prank(stranger);
        assertEq(distributor.claimed(recipient), 6 ether);
        vm.prank(recipient);
        assertEq(distributor.unclaimed(recipientB), 0);
        vm.prank(recipient);
        assertEq(distributor.claimed(recipientB), 0);
    }

    function test_AllocationRemainsClaimableAfterWarp() public {
        vm.prank(owner);
        distributor.allocate(recipient, 9 ether);

        vm.warp(block.timestamp + 10 * 365 days);

        assertEq(distributor.unclaimed(recipient), 9 ether);

        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(distributor.claimed(recipient), 9 ether);
        assertEq(token.balanceOf(recipient), 9 ether);
    }

    function test_InvariantHoldsAfterMixedAllocateBatchAndClaim() public {
        vm.prank(owner);
        distributor.allocate(recipient, 3 ether);

        vm.prank(recipient);
        distributor.claim();

        address[] memory recipients = new address[](2);
        recipients[0] = recipient;
        recipients[1] = recipientB;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2 ether;
        amounts[1] = 4 ether;

        vm.prank(owner);
        distributor.allocateBatch(recipients, amounts);

        uint256 unclaimedSum = distributor.unclaimed(recipient) + distributor.unclaimed(recipientB);
        assertEq(distributor.totalAllocated(), 9 ether);
        assertEq(distributor.totalClaimed(), 3 ether);
        assertEq(distributor.totalAllocated(), distributor.totalClaimed() + unclaimedSum);

        vm.prank(recipientB);
        distributor.claim();

        unclaimedSum = distributor.unclaimed(recipient) + distributor.unclaimed(recipientB);
        assertEq(distributor.totalAllocated(), distributor.totalClaimed() + unclaimedSum);
        assertEq(distributor.unclaimed(recipient), 2 ether);
        assertEq(distributor.unclaimed(recipientB), 0);
    }

    function test_AccountingViewsArePublicAndUnauthenticated() public view {
        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(distributor.claimed(recipient), 0);
        assertEq(distributor.totalAllocated(), 0);
        assertEq(distributor.totalClaimed(), 0);
    }
}
