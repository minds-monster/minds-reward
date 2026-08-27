// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Operable} from "../contracts/Operable.sol";
import {RewardToken} from "../contracts/RewardToken.sol";
import {RewardDistributor} from "../contracts/RewardDistributor.sol";

/// @dev FEAT-002 T1: Operable surface on both production contracts. allocate/mint auth
///      matrices land in T2/T3; this file does not change those guards.
interface IOperable {
    function owner() external view returns (address);
    function manager() external view returns (address);
    function setManager(address newManager) external;
    function transferOwnership(address newOwner) external;
    function renounceOwnership() external;
}

contract OperableTest is Test {
    RewardToken internal token;
    RewardDistributor internal distributor;

    address internal owner;
    address internal managerAddr;
    address internal otherManager;
    address internal newOwner;
    address internal stranger;

    event ManagerChanged(address indexed previousManager, address indexed newManager);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        owner = makeAddr("owner");
        managerAddr = makeAddr("manager");
        otherManager = makeAddr("otherManager");
        newOwner = makeAddr("newOwner");
        stranger = makeAddr("stranger");

        token = new RewardToken("Reward Token", "RWD", owner);
        distributor = new RewardDistributor(address(token), owner);
    }

    // --- AC-1 construction -------------------------------------------------------

    function test_TokenConstructorRevertsForZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new RewardToken("Reward Token", "RWD", address(0));
    }

    function test_DistributorConstructorRevertsForZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new RewardDistributor(address(token), address(0));
    }

    function test_BothContractsHaveConstructorOwner() public view {
        assertEq(token.owner(), owner);
        assertEq(distributor.owner(), owner);
        assertTrue(token.owner() != address(0));
        assertTrue(distributor.owner() != address(0));
    }

    // --- AC-7, AC-15 views -------------------------------------------------------

    function test_ManagerIsZeroAfterConstruction() public view {
        assertEq(token.manager(), address(0));
        assertEq(distributor.manager(), address(0));
    }

    function test_OwnerCanOperateWithNoManager() public {
        vm.startPrank(owner);
        token.setMinter(stranger);
        token.mint(stranger, 1 ether);
        distributor.allocate(stranger, 1 ether);
        vm.stopPrank();

        assertEq(token.minter(), stranger);
        assertEq(token.balanceOf(stranger), 1 ether);
        assertEq(distributor.unclaimed(stranger), 1 ether);
    }

    // --- AC-8, AC-9 setManager ---------------------------------------------------

    function test_OwnerSetManagerEmitsAndStoresOnBothContracts() public {
        _expectManagerChanged(address(token), address(0), managerAddr);
        vm.prank(owner);
        token.setManager(managerAddr);
        assertEq(token.manager(), managerAddr);

        _expectManagerChanged(address(distributor), address(0), managerAddr);
        vm.prank(owner);
        distributor.setManager(managerAddr);
        assertEq(distributor.manager(), managerAddr);
    }

    function test_OwnerReplacesManager() public {
        vm.prank(owner);
        token.setManager(managerAddr);

        _expectManagerChanged(address(token), managerAddr, otherManager);
        vm.prank(owner);
        token.setManager(otherManager);
        assertEq(token.manager(), otherManager);

        vm.expectRevert(abi.encodeWithSelector(RewardToken.NotAuthorizedToMint.selector, managerAddr));
        vm.prank(managerAddr);
        token.mint(stranger, 1 ether);

        vm.prank(otherManager);
        token.mint(stranger, 1 ether);
        assertEq(token.balanceOf(stranger), 1 ether);
    }

    function test_OwnerClearsManager() public {
        vm.prank(owner);
        token.setManager(managerAddr);

        _expectManagerChanged(address(token), managerAddr, address(0));
        vm.prank(owner);
        token.setManager(address(0));
        assertEq(token.manager(), address(0));
    }

    function test_SetManagerToCurrentValueStillEmits() public {
        vm.prank(owner);
        token.setManager(managerAddr);

        _expectManagerChanged(address(token), managerAddr, managerAddr);
        vm.prank(owner);
        token.setManager(managerAddr);
        assertEq(token.manager(), managerAddr);
    }

    function test_ClearingAlreadyEmptyManagerSucceedsAndEmits() public {
        _expectManagerChanged(address(token), address(0), address(0));
        vm.prank(owner);
        token.setManager(address(0));
        assertEq(token.manager(), address(0));
    }

    // --- AC-10 setManager unauthorized ------------------------------------------

    function test_StrangerSetManagerRevertsOnBothContracts() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        token.setManager(stranger);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        distributor.setManager(stranger);
    }

    function test_ManagerSetManagerRevertsOnBothContracts() public {
        vm.prank(owner);
        token.setManager(managerAddr);
        vm.prank(owner);
        distributor.setManager(managerAddr);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, managerAddr));
        vm.prank(managerAddr);
        token.setManager(otherManager);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, managerAddr));
        vm.prank(managerAddr);
        distributor.setManager(otherManager);
    }

    // --- AC-11 independent designations ------------------------------------------

    function test_ManagerDesignationsAreIndependent() public {
        vm.prank(owner);
        token.setManager(managerAddr);
        vm.prank(owner);
        distributor.setManager(otherManager);

        assertEq(token.manager(), managerAddr);
        assertEq(distributor.manager(), otherManager);

        vm.prank(owner);
        token.setManager(address(0));
        assertEq(token.manager(), address(0));
        assertEq(distributor.manager(), otherManager);
    }

    // --- AC-3, AC-4, AC-5 transferOwnership --------------------------------------

    function test_TransferOwnershipIsSingleStepOnBothContracts() public {
        vm.prank(owner);
        token.setManager(managerAddr);
        vm.prank(owner);
        distributor.setManager(managerAddr);

        vm.expectEmit(true, true, false, false, address(token));
        emit OwnershipTransferred(owner, newOwner);
        vm.prank(owner);
        token.transferOwnership(newOwner);

        assertEq(token.owner(), newOwner);
        assertEq(token.manager(), managerAddr);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        token.setManager(otherManager);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        token.transferOwnership(stranger);

        vm.prank(newOwner);
        token.setManager(otherManager);
        assertEq(token.manager(), otherManager);

        vm.expectEmit(true, true, false, false, address(distributor));
        emit OwnershipTransferred(owner, newOwner);
        vm.prank(owner);
        distributor.transferOwnership(newOwner);

        assertEq(distributor.owner(), newOwner);
        assertEq(distributor.manager(), managerAddr);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        distributor.setManager(otherManager);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        vm.prank(owner);
        distributor.transferOwnership(stranger);

        vm.prank(newOwner);
        distributor.setManager(otherManager);
        assertEq(distributor.manager(), otherManager);
    }

    function test_TransferOwnershipToZeroRevertsOnBothContracts() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        vm.prank(owner);
        token.transferOwnership(address(0));
        assertEq(token.owner(), owner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        vm.prank(owner);
        distributor.transferOwnership(address(0));
        assertEq(distributor.owner(), owner);
    }

    function test_NonOwnerTransferOwnershipRevertsOnBothContracts() public {
        vm.prank(owner);
        token.setManager(managerAddr);
        vm.prank(owner);
        distributor.setManager(managerAddr);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, managerAddr));
        vm.prank(managerAddr);
        token.transferOwnership(newOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        token.transferOwnership(newOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, managerAddr));
        vm.prank(managerAddr);
        distributor.transferOwnership(newOwner);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        distributor.transferOwnership(newOwner);

        assertEq(token.owner(), owner);
        assertEq(distributor.owner(), owner);
    }

    // --- AC-6 renounce -----------------------------------------------------------

    function test_RenounceOwnershipRevertsForOwnerOnBothContracts() public {
        vm.expectRevert(Operable.RenounceOwnershipDisabled.selector);
        vm.prank(owner);
        token.renounceOwnership();
        assertEq(token.owner(), owner);

        vm.expectRevert(Operable.RenounceOwnershipDisabled.selector);
        vm.prank(owner);
        distributor.renounceOwnership();
        assertEq(distributor.owner(), owner);
    }

    function test_RenounceOwnershipRevertsForStrangerOnBothContracts() public {
        vm.expectRevert(Operable.RenounceOwnershipDisabled.selector);
        vm.prank(stranger);
        token.renounceOwnership();
        assertEq(token.owner(), owner);

        vm.expectRevert(Operable.RenounceOwnershipDisabled.selector);
        vm.prank(stranger);
        distributor.renounceOwnership();
        assertEq(distributor.owner(), owner);
    }

    function _expectManagerChanged(address target, address previous, address next) private {
        vm.expectEmit(true, true, false, false, target);
        emit ManagerChanged(previous, next);
    }

    /// @dev Keeps the IOperable helper referenced so both ABIs are exercised as Operable.
    function test_BothContractsSatisfyIOperable() public view {
        IOperable tokenOps = IOperable(address(token));
        IOperable distOps = IOperable(address(distributor));
        assertEq(tokenOps.owner(), owner);
        assertEq(distOps.owner(), owner);
        assertEq(tokenOps.manager(), address(0));
        assertEq(distOps.manager(), address(0));
    }
}
