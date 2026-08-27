// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Operable} from "../contracts/Operable.sol";
import {RewardToken} from "../contracts/RewardToken.sol";
import {RewardDistributor} from "../contracts/RewardDistributor.sol";

/// @dev FEAT-005 T1: token pause control and freeze (AC-1..6, AC-9 token half).
contract RewardTokenPauseTest is Test {
    RewardToken internal token;

    address internal owner;
    address internal managerAddr;
    address internal minterAddr;
    address internal holder;
    address internal spender;
    address internal stranger;

    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        owner = makeAddr("owner");
        managerAddr = makeAddr("manager");
        minterAddr = makeAddr("minter");
        holder = makeAddr("holder");
        spender = makeAddr("spender");
        stranger = makeAddr("stranger");

        token = new RewardToken("Reward Token", "RWD", owner);

        vm.prank(owner);
        token.setManager(managerAddr);
        vm.prank(owner);
        token.setMinter(minterAddr);
    }

    // --- AC-1, FR-PAUSE-003 ------------------------------------------------------

    function test_TokenStartsUnpaused() public view {
        assertFalse(token.paused());
    }

    // --- AC-2, FR-PAUSE-001, FR-PAUSE-010, FR-OWN-006 ----------------------------

    function test_OwnerPauseEmitsPausedAndSetsFlag() public {
        vm.expectEmit(false, false, false, true, address(token));
        emit Paused(owner);

        vm.prank(owner);
        token.pause();

        assertTrue(token.paused());
    }

    function test_ManagerPauseEmitsPausedAndSetsFlag() public {
        vm.expectEmit(false, false, false, true, address(token));
        emit Paused(managerAddr);

        vm.prank(managerAddr);
        token.pause();

        assertTrue(token.paused());
    }

    function test_StrangerPauseRevertsNotOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operable.NotOperator.selector, stranger));
        vm.prank(stranger);
        token.pause();

        assertFalse(token.paused());
    }

    // --- AC-3, FR-PAUSE-002, FR-PAUSE-010 ----------------------------------------

    function test_OwnerUnpauseEmitsUnpausedAndClearsFlag() public {
        vm.prank(owner);
        token.pause();

        vm.expectEmit(false, false, false, true, address(token));
        emit Unpaused(owner);

        vm.prank(owner);
        token.unpause();

        assertFalse(token.paused());
    }

    function test_ManagerUnpauseEmitsUnpausedAndClearsFlag() public {
        vm.prank(owner);
        token.pause();

        vm.expectEmit(false, false, false, true, address(token));
        emit Unpaused(managerAddr);

        vm.prank(managerAddr);
        token.unpause();

        assertFalse(token.paused());
    }

    function test_StrangerUnpauseRevertsNotOperator() public {
        vm.prank(owner);
        token.pause();

        vm.expectRevert(abi.encodeWithSelector(Operable.NotOperator.selector, stranger));
        vm.prank(stranger);
        token.unpause();

        assertTrue(token.paused());
    }

    // --- AC-4, FR-PAUSE-011 ------------------------------------------------------

    function test_PauseWhilePausedRevertsEnforcedPause() public {
        vm.prank(owner);
        token.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(owner);
        token.pause();

        assertTrue(token.paused());
    }

    function test_UnpauseWhileUnpausedRevertsExpectedPause() public {
        vm.expectRevert(Pausable.ExpectedPause.selector);
        vm.prank(owner);
        token.unpause();

        assertFalse(token.paused());
    }

    // --- AC-5, FR-PAUSE-004, FR-PAUSE-009 ----------------------------------------

    function test_PausedTokenRejectsTransfersAndAcceptsApprove() public {
        vm.prank(owner);
        token.mint(holder, 5 ether);

        vm.prank(owner);
        token.pause();

        vm.prank(holder);
        token.approve(spender, 2 ether);
        assertEq(token.allowance(holder, spender), 2 ether);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(holder);
        token.transfer(spender, 1 ether);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(spender);
        token.transferFrom(holder, spender, 1 ether);

        assertEq(token.balanceOf(holder), 5 ether);
        assertEq(token.balanceOf(spender), 0);
    }

    // --- AC-6, FR-PAUSE-005 ------------------------------------------------------

    function test_PausedTokenRejectsMintFromOwnerManagerAndMinter() public {
        uint256 supplyBefore = token.totalSupply();

        vm.prank(owner);
        token.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(owner);
        token.mint(holder, 1 ether);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(managerAddr);
        token.mint(holder, 1 ether);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(minterAddr);
        token.mint(holder, 1 ether);

        assertEq(token.totalSupply(), supplyBefore);
        assertEq(token.balanceOf(holder), 0);
    }

    function test_UnauthorizedMintWhilePausedStillRevertsNotAuthorizedToMint() public {
        vm.prank(owner);
        token.pause();

        vm.expectRevert(abi.encodeWithSelector(RewardToken.NotAuthorizedToMint.selector, stranger));
        vm.prank(stranger);
        token.mint(holder, 1 ether);
    }

    // --- AC-9, FR-PAUSE-008 (token half) -----------------------------------------

    function test_TokenViewsRemainAvailableWhilePaused() public {
        vm.prank(owner);
        token.mint(holder, 3 ether);

        vm.prank(owner);
        token.pause();

        assertTrue(token.paused());
        assertEq(token.balanceOf(holder), 3 ether);
        assertEq(token.totalSupply(), 3 ether);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.owner(), owner);
        assertEq(token.manager(), managerAddr);
        assertEq(token.minter(), minterAddr);
    }
}

/// @dev FEAT-005 T2: distributor freeze, FR-CLAIM-012, and unpause restore (AC-7, AC-8,
///      AC-10, AC-11; distributor AC-1..4 / AC-9).
contract RewardDistributorPauseTest is Test {
    RewardToken internal token;
    RewardDistributor internal distributor;

    address internal owner;
    address internal managerAddr;
    address internal recipient;
    address internal recipientB;
    address internal holder;
    address internal stranger;

    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        owner = makeAddr("owner");
        managerAddr = makeAddr("manager");
        recipient = makeAddr("recipient");
        recipientB = makeAddr("recipientB");
        holder = makeAddr("holder");
        stranger = makeAddr("stranger");

        token = new RewardToken("Reward Token", "RWD", owner);
        distributor = new RewardDistributor(address(token), owner);

        vm.prank(owner);
        token.setMinter(address(distributor));
        vm.prank(owner);
        distributor.setManager(managerAddr);
        vm.prank(owner);
        token.setManager(managerAddr);
    }

    // --- AC-1, FR-PAUSE-003 ------------------------------------------------------

    function test_DistributorStartsUnpaused() public view {
        assertFalse(distributor.paused());
        assertFalse(token.paused());
    }

    // --- AC-2, FR-PAUSE-001, FR-PAUSE-010, FR-OWN-006 ----------------------------

    function test_OwnerPauseEmitsPausedAndSetsFlag() public {
        vm.expectEmit(false, false, false, true, address(distributor));
        emit Paused(owner);

        vm.prank(owner);
        distributor.pause();

        assertTrue(distributor.paused());
        assertFalse(token.paused());
    }

    function test_ManagerPauseEmitsPausedAndSetsFlag() public {
        vm.expectEmit(false, false, false, true, address(distributor));
        emit Paused(managerAddr);

        vm.prank(managerAddr);
        distributor.pause();

        assertTrue(distributor.paused());
    }

    function test_StrangerPauseRevertsNotOperator() public {
        vm.expectRevert(abi.encodeWithSelector(Operable.NotOperator.selector, stranger));
        vm.prank(stranger);
        distributor.pause();

        assertFalse(distributor.paused());
    }

    // --- AC-3, FR-PAUSE-002, FR-PAUSE-010 ----------------------------------------

    function test_OwnerUnpauseEmitsUnpausedAndClearsFlag() public {
        vm.prank(owner);
        distributor.pause();

        vm.expectEmit(false, false, false, true, address(distributor));
        emit Unpaused(owner);

        vm.prank(owner);
        distributor.unpause();

        assertFalse(distributor.paused());
    }

    function test_ManagerUnpauseEmitsUnpausedAndClearsFlag() public {
        vm.prank(owner);
        distributor.pause();

        vm.expectEmit(false, false, false, true, address(distributor));
        emit Unpaused(managerAddr);

        vm.prank(managerAddr);
        distributor.unpause();

        assertFalse(distributor.paused());
    }

    function test_StrangerUnpauseRevertsNotOperator() public {
        vm.prank(owner);
        distributor.pause();

        vm.expectRevert(abi.encodeWithSelector(Operable.NotOperator.selector, stranger));
        vm.prank(stranger);
        distributor.unpause();

        assertTrue(distributor.paused());
    }

    // --- AC-4, FR-PAUSE-011 ------------------------------------------------------

    function test_PauseWhilePausedRevertsEnforcedPause() public {
        vm.prank(owner);
        distributor.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(owner);
        distributor.pause();

        assertTrue(distributor.paused());
    }

    function test_UnpauseWhileUnpausedRevertsExpectedPause() public {
        vm.expectRevert(Pausable.ExpectedPause.selector);
        vm.prank(owner);
        distributor.unpause();

        assertFalse(distributor.paused());
    }

    // --- AC-7, FR-PAUSE-006, FR-PAUSE-012 ----------------------------------------

    function test_PausedDistributorRejectsClaimAndLeavesLedgerIntact() public {
        vm.prank(owner);
        distributor.allocate(recipient, 4 ether);

        vm.prank(owner);
        distributor.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 4 ether);
        assertEq(distributor.claimed(recipient), 0);
        assertEq(distributor.totalClaimed(), 0);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(owner);
        distributor.unpause();

        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(distributor.claimed(recipient), 4 ether);
        assertEq(distributor.totalClaimed(), 4 ether);
        assertEq(token.balanceOf(recipient), 4 ether);
    }

    // --- AC-8, FR-PAUSE-007 ------------------------------------------------------

    function test_PausedDistributorRejectsAllocateAndAllocateBatch() public {
        vm.prank(owner);
        distributor.allocate(recipient, 2 ether);
        uint256 allocatedBefore = distributor.totalAllocated();

        vm.prank(owner);
        distributor.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(owner);
        distributor.allocate(recipient, 1 ether);

        address[] memory recipients = new address[](1);
        recipients[0] = recipientB;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 3 ether;

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(owner);
        distributor.allocateBatch(recipients, amounts);

        assertEq(distributor.unclaimed(recipient), 2 ether);
        assertEq(distributor.unclaimed(recipientB), 0);
        assertEq(distributor.totalAllocated(), allocatedBefore);
    }

    function test_StrangerAllocateWhilePausedRevertsNotOperator() public {
        vm.prank(owner);
        distributor.pause();

        vm.expectRevert(abi.encodeWithSelector(Operable.NotOperator.selector, stranger));
        vm.prank(stranger);
        distributor.allocate(recipient, 1 ether);
    }

    // --- AC-9, FR-PAUSE-008 (distributor half) -----------------------------------

    function test_DistributorViewsRemainAvailableWhilePaused() public {
        vm.prank(owner);
        distributor.allocate(recipient, 5 ether);
        vm.prank(recipient);
        distributor.claim();
        vm.prank(owner);
        distributor.allocate(recipient, 2 ether);

        vm.prank(owner);
        distributor.pause();

        assertTrue(distributor.paused());
        assertEq(distributor.unclaimed(recipient), 2 ether);
        assertEq(distributor.claimed(recipient), 5 ether);
        assertEq(distributor.totalAllocated(), 7 ether);
        assertEq(distributor.totalClaimed(), 5 ether);
        assertEq(distributor.owner(), owner);
        assertEq(distributor.manager(), managerAddr);
        assertEq(address(distributor.token()), address(token));
    }

    // --- AC-10, FR-CLAIM-012, UC-09 1b -------------------------------------------

    function test_PausedTokenUnpausedDistributorRejectsClaimAndLeavesLedgerIntact() public {
        vm.prank(owner);
        distributor.allocate(recipient, 3 ether);

        vm.prank(owner);
        token.pause();
        assertFalse(distributor.paused());

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 3 ether);
        assertEq(distributor.claimed(recipient), 0);
        assertEq(distributor.totalClaimed(), 0);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(owner);
        token.unpause();

        vm.prank(recipient);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(distributor.claimed(recipient), 3 ether);
        assertEq(distributor.totalClaimed(), 3 ether);
        assertEq(token.balanceOf(recipient), 3 ether);
    }

    // --- AC-11, FR-PAUSE-012 -----------------------------------------------------

    function test_PauseThenUnpauseRestoresStateAndFunctionality() public {
        vm.prank(owner);
        token.mint(holder, 10 ether);
        vm.prank(owner);
        distributor.allocate(recipient, 4 ether);
        vm.prank(recipient);
        distributor.claim();
        vm.prank(owner);
        distributor.allocate(recipient, 2 ether);

        uint256 holderBalance = token.balanceOf(holder);
        uint256 recipientBalance = token.balanceOf(recipient);
        uint256 supply = token.totalSupply();
        uint256 unclaimedAmount = distributor.unclaimed(recipient);
        uint256 claimedAmount = distributor.claimed(recipient);
        uint256 totalAllocated_ = distributor.totalAllocated();
        uint256 totalClaimed_ = distributor.totalClaimed();

        vm.startPrank(owner);
        token.pause();
        distributor.pause();
        token.unpause();
        distributor.unpause();
        vm.stopPrank();

        assertEq(token.balanceOf(holder), holderBalance);
        assertEq(token.balanceOf(recipient), recipientBalance);
        assertEq(token.totalSupply(), supply);
        assertEq(distributor.unclaimed(recipient), unclaimedAmount);
        assertEq(distributor.claimed(recipient), claimedAmount);
        assertEq(distributor.totalAllocated(), totalAllocated_);
        assertEq(distributor.totalClaimed(), totalClaimed_);

        vm.prank(holder);
        token.transfer(stranger, 1 ether);
        assertEq(token.balanceOf(stranger), 1 ether);

        vm.prank(owner);
        token.mint(holder, 1 ether);

        vm.prank(owner);
        distributor.allocate(recipientB, 1 ether);
        assertEq(distributor.unclaimed(recipientB), 1 ether);

        vm.prank(recipient);
        distributor.claim();
        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(token.balanceOf(recipient), recipientBalance + unclaimedAmount);
    }
}
