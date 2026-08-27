// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Operable} from "../contracts/Operable.sol";
import {RewardToken} from "../contracts/RewardToken.sol";
import {RewardDistributor} from "../contracts/RewardDistributor.sol";

/// @dev Walking-skeleton unit tests. Scope matches FEAT-001: the happy paths plus every
/// revert path the skeleton's own code contains, which is what keeps the 100% line and
/// branch gate (NFR-MNT-001) green from the first commit. The exhaustive per-requirement
/// suites arrive with the slices that add the behavior.
contract RewardSystemTest is Test {
    RewardToken internal token;
    RewardDistributor internal distributor;

    address internal owner;
    address internal managerAddr;
    address internal recipient;
    address internal stranger;

    event MinterChanged(address indexed previousMinter, address indexed newMinter);
    event Allocated(address indexed recipient, uint256 amount, uint256 unclaimedTotal);
    event Claimed(address indexed recipient, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        owner = makeAddr("owner");
        managerAddr = makeAddr("manager");
        recipient = makeAddr("recipient");
        stranger = makeAddr("stranger");

        token = new RewardToken("Reward Token", "RWD", owner);
        distributor = new RewardDistributor(address(token), owner);

        vm.prank(owner);
        token.setMinter(address(distributor));
    }

    // --- RewardToken -------------------------------------------------------------

    function test_TokenMetadata() public view {
        assertEq(token.name(), "Reward Token");
        assertEq(token.symbol(), "RWD");
        assertEq(token.decimals(), 18);
        assertEq(token.owner(), owner);
        assertEq(token.totalSupply(), 0);
    }

    function test_SetMinterEmitsAndStores() public {
        vm.expectEmit(true, true, false, false);
        emit MinterChanged(address(distributor), stranger);

        vm.prank(owner);
        token.setMinter(stranger);

        assertEq(token.minter(), stranger);
    }

    function test_SetMinterRevertsForNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        token.setMinter(stranger);
    }

    function test_OwnerCanMint() public {
        vm.prank(owner);
        token.mint(recipient, 5 ether);

        assertEq(token.balanceOf(recipient), 5 ether);
        assertEq(token.totalSupply(), 5 ether);
    }

    function test_MinterCanMint() public {
        vm.prank(address(distributor));
        token.mint(recipient, 1 ether);

        assertEq(token.balanceOf(recipient), 1 ether);
    }

    function test_MintRevertsForUnauthorizedCaller() public {
        vm.expectRevert(abi.encodeWithSelector(RewardToken.NotAuthorizedToMint.selector, stranger));
        vm.prank(stranger);
        token.mint(recipient, 1 ether);
    }

    function test_ManagerCanMint() public {
        vm.prank(owner);
        token.setManager(managerAddr);

        vm.prank(managerAddr);
        token.mint(recipient, 4 ether);

        assertEq(token.balanceOf(recipient), 4 ether);
        assertEq(token.totalSupply(), 4 ether);
    }

    function test_OwnerAndMinterCanMintAfterManagerIsSet() public {
        vm.prank(owner);
        token.setManager(managerAddr);

        vm.prank(owner);
        token.mint(recipient, 1 ether);
        vm.prank(address(distributor));
        token.mint(recipient, 2 ether);

        assertEq(token.balanceOf(recipient), 3 ether);
    }

    function test_ManagerSetMinterReverts() public {
        vm.prank(owner);
        token.setManager(managerAddr);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, managerAddr));
        vm.prank(managerAddr);
        token.setMinter(stranger);

        assertEq(token.minter(), address(distributor));
    }

    function test_ClearedManagerCannotMint() public {
        vm.startPrank(owner);
        token.setManager(managerAddr);
        token.setManager(address(0));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(RewardToken.NotAuthorizedToMint.selector, managerAddr));
        vm.prank(managerAddr);
        token.mint(recipient, 1 ether);
    }

    function test_MintRevertsForZeroRecipient() public {
        vm.expectRevert(RewardToken.MintToZeroAddress.selector);
        vm.prank(owner);
        token.mint(address(0), 1 ether);
    }

    // --- RewardDistributor -------------------------------------------------------

    function test_DistributorRevertsOnZeroToken() public {
        vm.expectRevert(RewardDistributor.TokenAddressZero.selector);
        new RewardDistributor(address(0), owner);
    }

    function test_DistributorBindsTokenAndOwner() public view {
        assertEq(address(distributor.token()), address(token));
        assertEq(distributor.owner(), owner);
        assertEq(distributor.unclaimed(stranger), 0);
    }

    function test_AllocateEmitsAndStores() public {
        vm.expectEmit(true, false, false, true);
        emit Allocated(recipient, 3 ether, 3 ether);

        vm.prank(owner);
        distributor.allocate(recipient, 3 ether);

        assertEq(distributor.unclaimed(recipient), 3 ether);
    }

    function test_AllocateAccumulates() public {
        vm.startPrank(owner);
        distributor.allocate(recipient, 2 ether);
        distributor.allocate(recipient, 4 ether);
        vm.stopPrank();

        assertEq(distributor.unclaimed(recipient), 6 ether);
    }

    function test_AllocateRevertsForZeroRecipient() public {
        vm.expectRevert(RewardDistributor.AllocationToZeroAddress.selector);
        vm.prank(owner);
        distributor.allocate(address(0), 1 ether);
    }

    function test_AllocateRevertsForNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Operable.NotOperator.selector, stranger));
        vm.prank(stranger);
        distributor.allocate(recipient, 1 ether);
    }

    function test_ManagerCanAllocate() public {
        vm.prank(owner);
        distributor.setManager(managerAddr);

        vm.expectEmit(true, false, false, true);
        emit Allocated(recipient, 3 ether, 3 ether);

        vm.prank(managerAddr);
        distributor.allocate(recipient, 3 ether);

        assertEq(distributor.unclaimed(recipient), 3 ether);
    }

    function test_OwnerCanAllocateAfterManagerIsSet() public {
        vm.prank(owner);
        distributor.setManager(managerAddr);

        vm.prank(owner);
        distributor.allocate(recipient, 2 ether);

        assertEq(distributor.unclaimed(recipient), 2 ether);
    }

    function test_ClearedManagerCannotAllocate() public {
        vm.startPrank(owner);
        distributor.setManager(managerAddr);
        distributor.setManager(address(0));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Operable.NotOperator.selector, managerAddr));
        vm.prank(managerAddr);
        distributor.allocate(recipient, 1 ether);
    }

    function test_ReplacedManagerCannotAllocate() public {
        address replacement = makeAddr("replacement");

        vm.startPrank(owner);
        distributor.setManager(managerAddr);
        distributor.setManager(replacement);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Operable.NotOperator.selector, managerAddr));
        vm.prank(managerAddr);
        distributor.allocate(recipient, 1 ether);

        vm.prank(replacement);
        distributor.allocate(recipient, 1 ether);
        assertEq(distributor.unclaimed(recipient), 1 ether);
    }

    function test_ClaimMintsAndZeroesAllocation() public {
        vm.prank(owner);
        distributor.allocate(recipient, 7 ether);

        vm.expectEmit(true, false, false, true, address(distributor));
        emit Claimed(recipient, 7 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(0), recipient, 7 ether);

        vm.prank(recipient);
        distributor.claim();

        assertEq(token.balanceOf(recipient), 7 ether);
        assertEq(distributor.unclaimed(recipient), 0);
        assertEq(token.totalSupply(), 7 ether);
    }

    function test_ClaimRevertsWhenNothingOwed() public {
        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.NothingToClaim.selector, stranger));
        vm.prank(stranger);
        distributor.claim();

        assertEq(token.totalSupply(), 0);
        assertEq(distributor.unclaimed(stranger), 0);
    }

    function test_StrangerCannotClaimRecipientAllocation() public {
        vm.prank(owner);
        distributor.allocate(recipient, 4 ether);

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.NothingToClaim.selector, stranger));
        vm.prank(stranger);
        distributor.claim();

        assertEq(distributor.unclaimed(recipient), 4 ether);
        assertEq(token.balanceOf(stranger), 0);
        assertEq(token.totalSupply(), 0);
    }

    function test_RepeatClaimRevertsUntilReallocated() public {
        vm.prank(owner);
        distributor.allocate(recipient, 1 ether);

        vm.prank(recipient);
        distributor.claim();

        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.NothingToClaim.selector, recipient));
        vm.prank(recipient);
        distributor.claim();
    }
}
