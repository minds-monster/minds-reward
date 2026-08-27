// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Operable} from "../contracts/Operable.sol";
import {RewardToken} from "../contracts/RewardToken.sol";
import {RewardDistributor} from "../contracts/RewardDistributor.sol";

/// @dev FEAT-006: allocation ledger — single-path criteria (AC-1..5) here; batch in T2.
contract RewardDistributorAllocationTest is Test {
    RewardToken internal token;
    RewardDistributor internal distributor;

    address internal owner;
    address internal managerAddr;
    address internal recipient;
    address internal recipientB;
    address internal stranger;

    event Allocated(address indexed recipient, uint256 amount, uint256 unclaimedTotal);

    function setUp() public {
        owner = makeAddr("owner");
        managerAddr = makeAddr("manager");
        recipient = makeAddr("recipient");
        recipientB = makeAddr("recipientB");
        stranger = makeAddr("stranger");

        token = new RewardToken("Reward Token", "RWD", owner);
        distributor = new RewardDistributor(address(token), owner);
    }

    // --- AC-1, AC-2, FR-ALLOC-001, FR-ALLOC-002, FR-ALLOC-012 --------------------

    function test_AllocateCreditsUnclaimedAndEmitsAllocated() public {
        vm.expectEmit(true, false, false, true, address(distributor));
        emit Allocated(recipient, 3 ether, 3 ether);

        vm.prank(owner);
        distributor.allocate(recipient, 3 ether);

        assertEq(distributor.unclaimed(recipient), 3 ether);
    }

    function test_AllocateIsAdditiveNotReplacement() public {
        vm.startPrank(owner);
        distributor.allocate(recipient, 2 ether);
        vm.expectEmit(true, false, false, true, address(distributor));
        emit Allocated(recipient, 4 ether, 6 ether);
        distributor.allocate(recipient, 4 ether);
        vm.stopPrank();

        assertEq(distributor.unclaimed(recipient), 6 ether);
    }

    // --- AC-3, FR-ALLOC-007 ------------------------------------------------------

    function test_AllocateToZeroAddressRevertsAndLeavesUnclaimedUnchanged() public {
        vm.prank(owner);
        distributor.allocate(recipient, 1 ether);

        vm.expectRevert(RewardDistributor.AllocationToZeroAddress.selector);
        vm.prank(owner);
        distributor.allocate(address(0), 5 ether);

        assertEq(distributor.unclaimed(recipient), 1 ether);
        assertEq(distributor.unclaimed(address(0)), 0);
    }

    // --- AC-4, FR-ALLOC-008 ------------------------------------------------------

    function test_AllocateZeroAmountRevertsAndLeavesUnclaimedUnchanged() public {
        vm.prank(owner);
        distributor.allocate(recipient, 1 ether);

        vm.expectRevert(RewardDistributor.AllocationAmountZero.selector);
        vm.prank(owner);
        distributor.allocate(recipient, 0);

        assertEq(distributor.unclaimed(recipient), 1 ether);
    }

    function test_AllocateZeroAmountToFreshRecipientReverts() public {
        vm.expectRevert(RewardDistributor.AllocationAmountZero.selector);
        vm.prank(owner);
        distributor.allocate(recipient, 0);

        assertEq(distributor.unclaimed(recipient), 0);
    }

    // --- AC-5, FR-OWN-006, FR-OWN-008 --------------------------------------------

    function test_StrangerAllocateRevertsNotOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operable.NotOperator.selector, stranger));
        vm.prank(stranger);
        distributor.allocate(recipient, 1 ether);

        assertEq(distributor.unclaimed(recipient), 0);
    }

    function test_ManagerCanAllocate() public {
        vm.prank(owner);
        distributor.setManager(managerAddr);

        vm.expectEmit(true, false, false, true, address(distributor));
        emit Allocated(recipient, 3 ether, 3 ether);

        vm.prank(managerAddr);
        distributor.allocate(recipient, 3 ether);

        assertEq(distributor.unclaimed(recipient), 3 ether);
    }

    function test_StrangerAllocateBatchRevertsNotOperator() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.expectRevert(abi.encodeWithSelector(Operable.NotOperator.selector, stranger));
        vm.prank(stranger);
        distributor.allocateBatch(recipients, amounts);

        assertEq(distributor.unclaimed(recipient), 0);
    }

    function test_ManagerCanAllocateBatch() public {
        vm.prank(owner);
        distributor.setManager(managerAddr);

        address[] memory recipients = new address[](1);
        recipients[0] = recipient;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2 ether;

        vm.expectEmit(true, false, false, true, address(distributor));
        emit Allocated(recipient, 2 ether, 2 ether);

        vm.prank(managerAddr);
        distributor.allocateBatch(recipients, amounts);

        assertEq(distributor.unclaimed(recipient), 2 ether);
    }

    // --- AC-6, FR-ALLOC-003, FR-ALLOC-012 ----------------------------------------

    function test_AllocateBatchCreditsEachRecipientAndEmitsPerEntry() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient;
        recipients[1] = recipientB;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 5 ether;

        vm.expectEmit(true, false, false, true, address(distributor));
        emit Allocated(recipient, 1 ether, 1 ether);
        vm.expectEmit(true, false, false, true, address(distributor));
        emit Allocated(recipientB, 5 ether, 5 ether);

        vm.prank(owner);
        distributor.allocateBatch(recipients, amounts);

        assertEq(distributor.unclaimed(recipient), 1 ether);
        assertEq(distributor.unclaimed(recipientB), 5 ether);
    }

    // --- AC-7, FR-ALLOC-005 ------------------------------------------------------

    function test_AllocateBatchLengthMismatchRevertsAndLeavesUnclaimedUnchanged() public {
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

        assertEq(distributor.unclaimed(recipient), 1 ether);
        assertEq(distributor.unclaimed(recipientB), 0);
    }

    function test_AllocateBatchEmptyRecipientsNonEmptyAmountsIsLengthMismatch() public {
        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1 ether;

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.AllocationLengthMismatch.selector, 0, 1));
        vm.prank(owner);
        distributor.allocateBatch(recipients, amounts);
    }

    // --- AC-8, FR-ALLOC-006, D2 --------------------------------------------------

    function test_AllocateBatchEmptyListsRevertEmptyBatch() public {
        vm.prank(owner);
        distributor.allocate(recipient, 1 ether);

        address[] memory recipients = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert(RewardDistributor.EmptyBatch.selector);
        vm.prank(owner);
        distributor.allocateBatch(recipients, amounts);

        assertEq(distributor.unclaimed(recipient), 1 ether);
    }

    // --- AC-9, FR-ALLOC-004 ------------------------------------------------------

    function test_AllocateBatchRevertsOnLastZeroAddressAndKeepsNoEarlierCredits() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient;
        recipients[1] = address(0);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 4 ether;
        amounts[1] = 1 ether;

        vm.expectRevert(RewardDistributor.AllocationToZeroAddress.selector);
        vm.prank(owner);
        distributor.allocateBatch(recipients, amounts);

        assertEq(distributor.unclaimed(recipient), 0);
    }

    function test_AllocateBatchRevertsOnLastZeroAmountAndKeepsNoEarlierCredits() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient;
        recipients[1] = recipientB;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 4 ether;
        amounts[1] = 0;

        vm.expectRevert(RewardDistributor.AllocationAmountZero.selector);
        vm.prank(owner);
        distributor.allocateBatch(recipients, amounts);

        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(distributor.unclaimed(recipientB), 0);
    }

    // --- AC-10, FR-ALLOC-009 -----------------------------------------------------

    function test_AllocateBatchDuplicateAddressAccumulatesAndEmitsPerEntry() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient;
        recipients[1] = recipient;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;

        vm.expectEmit(true, false, false, true, address(distributor));
        emit Allocated(recipient, 1 ether, 1 ether);
        vm.expectEmit(true, false, false, true, address(distributor));
        emit Allocated(recipient, 2 ether, 3 ether);

        vm.prank(owner);
        distributor.allocateBatch(recipients, amounts);

        assertEq(distributor.unclaimed(recipient), 3 ether);
    }
}

/// @dev FEAT-008: claim hardening — first-claim (AC-1..3) and guards (AC-5..9).
contract RewardDistributorClaimTest is Test {
    RewardToken internal token;
    RewardDistributor internal distributor;

    address internal owner;
    address internal recipient;
    address internal stranger;

    event Claimed(address indexed recipient, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");
        stranger = makeAddr("stranger");

        token = new RewardToken("Reward Token", "RWD", owner);
        distributor = new RewardDistributor(address(token), owner);

        vm.prank(owner);
        token.setMinter(address(distributor));
    }

    function test_ClaimPaysEntireAmountMintsAndZeroesUnclaimed() public {
        vm.prank(owner);
        distributor.allocate(recipient, 7 ether);

        vm.expectEmit(true, false, false, true, address(distributor));
        emit Claimed(recipient, 7 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(0), recipient, 7 ether);

        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(token.balanceOf(recipient), 7 ether);
        assertEq(token.totalSupply(), 7 ether);
        assertEq(distributor.claimed(recipient), 7 ether);
        assertEq(distributor.totalClaimed(), 7 ether);
    }

    function test_StrangerCannotClaimRecipientAllocation() public {
        vm.prank(owner);
        distributor.allocate(recipient, 4 ether);

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.NothingToClaim.selector, stranger));
        vm.prank(stranger);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 4 ether);
        assertEq(distributor.unclaimed(stranger), 0);
        assertEq(token.balanceOf(stranger), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), 0);
        assertEq(distributor.claimed(recipient), 0);
        assertEq(distributor.claimed(stranger), 0);
        assertEq(distributor.totalClaimed(), 0);
    }

    function test_ClaimRevertsWhenNothingOwedAndLeavesStateUnchanged() public {
        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.NothingToClaim.selector, stranger));
        vm.prank(stranger);
        distributor.claim();

        assertEq(token.totalSupply(), 0);
        assertEq(distributor.unclaimed(stranger), 0);
        assertEq(distributor.claimed(stranger), 0);
        assertEq(distributor.totalClaimed(), 0);
    }

    function test_ImmediateRepeatClaimRevertsAndLeavesClaimedTotalsUnchanged() public {
        vm.prank(owner);
        distributor.allocate(recipient, 3 ether);

        vm.prank(recipient);
        distributor.claim();

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.NothingToClaim.selector, recipient));
        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(token.balanceOf(recipient), 3 ether);
        assertEq(token.totalSupply(), 3 ether);
        assertEq(distributor.claimed(recipient), 3 ether);
        assertEq(distributor.totalClaimed(), 3 ether);
    }

    function test_AllocateClaimCycleRepeatsAndAccumulatesClaimedTotals() public {
        vm.prank(owner);
        distributor.allocate(recipient, 2 ether);

        vm.prank(recipient);
        distributor.claim();

        vm.prank(owner);
        distributor.allocate(recipient, 5 ether);

        vm.expectEmit(true, false, false, true, address(distributor));
        emit Claimed(recipient, 5 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(0), recipient, 5 ether);

        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(token.balanceOf(recipient), 7 ether);
        assertEq(token.totalSupply(), 7 ether);
        assertEq(distributor.claimed(recipient), 7 ether);
        assertEq(distributor.totalClaimed(), 7 ether);

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.NothingToClaim.selector, recipient));
        vm.prank(recipient);
        distributor.claim();
    }

    function test_ClearedMinterRevertsClaimAndLeavesAllocationIntact() public {
        vm.prank(owner);
        distributor.allocate(recipient, 6 ether);

        vm.prank(owner);
        token.setMinter(address(0));

        vm.expectRevert(
            abi.encodeWithSelector(RewardToken.NotAuthorizedToMint.selector, address(distributor))
        );
        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 6 ether);
        assertEq(distributor.claimed(recipient), 0);
        assertEq(distributor.totalClaimed(), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), 0);

        vm.prank(owner);
        token.setMinter(address(distributor));

        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(distributor.claimed(recipient), 6 ether);
        assertEq(distributor.totalClaimed(), 6 ether);
        assertEq(token.balanceOf(recipient), 6 ether);
    }

    function test_ReplacedMinterRevertsClaimAndLeavesAllocationIntact() public {
        address otherMinter = makeAddr("otherMinter");

        vm.prank(owner);
        distributor.allocate(recipient, 8 ether);

        vm.prank(owner);
        token.setMinter(otherMinter);

        vm.expectRevert(
            abi.encodeWithSelector(RewardToken.NotAuthorizedToMint.selector, address(distributor))
        );
        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 8 ether);
        assertEq(distributor.claimed(recipient), 0);
        assertEq(distributor.totalClaimed(), 0);
        assertEq(token.totalSupply(), 0);

        vm.prank(owner);
        token.setMinter(address(distributor));

        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(distributor.claimed(recipient), 8 ether);
        assertEq(distributor.totalClaimed(), 8 ether);
    }
}
