// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {RewardToken} from "../contracts/RewardToken.sol";

/// @dev FEAT-004: complete minting and minter-designation matrix (FR-SUP-001..009).
contract RewardTokenMintingTest is Test {
    RewardToken internal token;

    address internal owner;
    address internal managerAddr;
    address internal minterAddr;
    address internal recipient;
    address internal stranger;

    event MinterChanged(address indexed previousMinter, address indexed newMinter);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        owner = makeAddr("owner");
        managerAddr = makeAddr("manager");
        minterAddr = makeAddr("minter");
        recipient = makeAddr("recipient");
        stranger = makeAddr("stranger");

        token = new RewardToken("Reward Token", "RWD", owner);
    }

    function test_OwnerMintIncreasesSupplyAndEmitsTransfer() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(0), recipient, 5 ether);

        vm.prank(owner);
        token.mint(recipient, 5 ether);

        assertEq(token.balanceOf(recipient), 5 ether);
        assertEq(token.totalSupply(), 5 ether);
    }

    function test_ManagerMintIncreasesSupplyAndEmitsTransfer() public {
        vm.prank(owner);
        token.setManager(managerAddr);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(0), recipient, 4 ether);

        vm.prank(managerAddr);
        token.mint(recipient, 4 ether);

        assertEq(token.balanceOf(recipient), 4 ether);
        assertEq(token.totalSupply(), 4 ether);
    }

    function test_MinterMintIncreasesSupplyAndEmitsTransfer() public {
        vm.prank(owner);
        token.setMinter(minterAddr);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(0), recipient, 3 ether);

        vm.prank(minterAddr);
        token.mint(recipient, 3 ether);

        assertEq(token.balanceOf(recipient), 3 ether);
        assertEq(token.totalSupply(), 3 ether);
    }

    function test_UnauthorizedMintRevertsAndLeavesStateUnchanged() public {
        vm.expectRevert(abi.encodeWithSelector(RewardToken.NotAuthorizedToMint.selector, stranger));
        vm.prank(stranger);
        token.mint(recipient, 1 ether);

        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), 0);
    }

    function test_MintToZeroRevertsAndLeavesSupplyUnchanged() public {
        uint256 supplyBefore = token.totalSupply();

        vm.expectRevert(RewardToken.MintToZeroAddress.selector);
        vm.prank(owner);
        token.mint(address(0), 1 ether);

        assertEq(token.totalSupply(), supplyBefore);
    }

    function test_SetMinterEmitsIndexedPreviousAndNew() public {
        vm.expectEmit(true, true, false, false, address(token));
        emit MinterChanged(address(0), minterAddr);

        vm.prank(owner);
        token.setMinter(minterAddr);

        assertEq(token.minter(), minterAddr);
    }

    function test_ClearingMinterRevokesPreviousAndOwnerCanStillMint() public {
        vm.prank(owner);
        token.setMinter(minterAddr);

        vm.expectEmit(true, true, false, false, address(token));
        emit MinterChanged(minterAddr, address(0));
        vm.prank(owner);
        token.setMinter(address(0));
        assertEq(token.minter(), address(0));

        vm.expectRevert(abi.encodeWithSelector(RewardToken.NotAuthorizedToMint.selector, minterAddr));
        vm.prank(minterAddr);
        token.mint(recipient, 1 ether);

        vm.prank(owner);
        token.mint(recipient, 1 ether);
        assertEq(token.balanceOf(recipient), 1 ether);
    }

    function test_ReplacingMinterRevokesPrevious() public {
        address nextMinter = makeAddr("nextMinter");

        vm.prank(owner);
        token.setMinter(minterAddr);
        vm.prank(owner);
        token.setMinter(nextMinter);

        vm.expectRevert(abi.encodeWithSelector(RewardToken.NotAuthorizedToMint.selector, minterAddr));
        vm.prank(minterAddr);
        token.mint(recipient, 1 ether);

        vm.prank(nextMinter);
        token.mint(recipient, 2 ether);
        assertEq(token.balanceOf(recipient), 2 ether);
        assertEq(token.minter(), nextMinter);
    }

    function test_SetMinterToCurrentValueStillEmits() public {
        vm.prank(owner);
        token.setMinter(minterAddr);

        vm.expectEmit(true, true, false, false, address(token));
        emit MinterChanged(minterAddr, minterAddr);
        vm.prank(owner);
        token.setMinter(minterAddr);
        assertEq(token.minter(), minterAddr);
    }

    function test_StrangerSetMinterReverts() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        token.setMinter(stranger);
        assertEq(token.minter(), address(0));
    }

    function test_ManagerSetMinterReverts() public {
        vm.prank(owner);
        token.setManager(managerAddr);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, managerAddr));
        vm.prank(managerAddr);
        token.setMinter(minterAddr);
        assertEq(token.minter(), address(0));
    }

    function test_SecondMintSucceedsWithoutCap() public {
        vm.startPrank(owner);
        token.mint(recipient, 1 ether);
        token.mint(recipient, 2 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), 3 ether);
        assertEq(token.totalSupply(), 3 ether);
    }
}
