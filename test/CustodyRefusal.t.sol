// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {RewardToken} from "../contracts/RewardToken.sol";
import {RewardDistributor} from "../contracts/RewardDistributor.sol";

/// @dev Bubbles a low-level call revert so `vm.expectRevert` can see `EtherRejected`.
contract EtherSender {
    function ping(address to, bytes calldata data) external payable {
        (bool ok, bytes memory ret) = to.call{value: msg.value}(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
    }
}

/// @dev FEAT-009 T1: ETH rejection on both contracts (AC-1..3, FR-RESC-002).
contract CustodyRefusalEthTest is Test {
    RewardToken internal token;
    RewardDistributor internal distributor;
    EtherSender internal sender;

    address internal owner;
    address internal holder;

    function setUp() public {
        owner = makeAddr("owner");
        holder = makeAddr("holder");

        token = new RewardToken("Reward Token", "RWD", owner);
        distributor = new RewardDistributor(address(token), owner);
        sender = new EtherSender();
        vm.deal(address(sender), 10 ether);
    }

    // --- AC-1, FR-RESC-002 -------------------------------------------------------

    function test_TokenRejectsPlainEthWithEtherRejected() public {
        vm.expectRevert(RewardToken.EtherRejected.selector);
        sender.ping{value: 1 ether}(address(token), "");

        assertEq(address(token).balance, 0);
        assertEq(address(sender).balance, 10 ether);
    }

    function test_DistributorRejectsPlainEthWithEtherRejected() public {
        vm.expectRevert(RewardDistributor.EtherRejected.selector);
        sender.ping{value: 1 ether}(address(distributor), "");

        assertEq(address(distributor).balance, 0);
        assertEq(address(sender).balance, 10 ether);
    }

    // --- AC-2, FR-RESC-002 -------------------------------------------------------

    function test_TokenRejectsEthWithUnknownSelector() public {
        vm.expectRevert(RewardToken.EtherRejected.selector);
        sender.ping{value: 1 ether}(address(token), hex"deadbeef");

        assertEq(address(token).balance, 0);
    }

    function test_DistributorRejectsEthWithUnknownSelector() public {
        vm.expectRevert(RewardDistributor.EtherRejected.selector);
        sender.ping{value: 1 ether}(address(distributor), hex"deadbeef");

        assertEq(address(distributor).balance, 0);
    }

    // --- AC-3, FR-RESC-002 -------------------------------------------------------

    function test_TokenTransferWithValueDoesNotAcceptEth() public {
        vm.prank(owner);
        token.mint(holder, 1 ether);
        vm.deal(holder, 1 ether);

        vm.prank(holder);
        (bool ok, ) = address(token).call{value: 1 ether}(
            abi.encodeWithSelector(token.transfer.selector, holder, 1 ether)
        );

        assertFalse(ok);
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(holder), 1 ether);
        assertEq(holder.balance, 1 ether);
    }

    function test_DistributorClaimWithValueDoesNotAcceptEth() public {
        vm.prank(owner);
        token.setMinter(address(distributor));
        vm.prank(owner);
        distributor.allocate(holder, 1 ether);
        vm.deal(holder, 1 ether);

        vm.prank(holder);
        (bool ok, ) = address(distributor).call{value: 1 ether}(
            abi.encodeWithSelector(distributor.claim.selector)
        );

        assertFalse(ok);
        assertEq(address(distributor).balance, 0);
        assertEq(distributor.unclaimed(holder), 1 ether);
        assertEq(token.balanceOf(holder), 0);
        assertEq(holder.balance, 1 ether);
    }
}

/// @dev FEAT-009 T2: no rescue, operate with empty balances (AC-5..7, FR-RESC-001, FR-RESC-003).
contract CustodyRefusalBalanceTest is Test {
    RewardToken internal token;
    RewardDistributor internal distributor;

    address internal owner;
    address internal holder;
    address internal recipient;

    function setUp() public {
        owner = makeAddr("owner");
        holder = makeAddr("holder");
        recipient = makeAddr("recipient");

        token = new RewardToken("Reward Token", "RWD", owner);
        distributor = new RewardDistributor(address(token), owner);

        vm.prank(owner);
        token.setMinter(address(distributor));
    }

    // --- AC-5, FR-RESC-003 -------------------------------------------------------

    function test_ClaimSucceedsWithZeroDistributorEthAndTokenBalance() public {
        vm.prank(owner);
        distributor.allocate(recipient, 3 ether);

        assertEq(address(distributor).balance, 0);
        assertEq(token.balanceOf(address(distributor)), 0);

        vm.prank(recipient);
        distributor.claim();

        assertEq(token.balanceOf(recipient), 3 ether);
        assertEq(token.totalSupply(), 3 ether);
        assertEq(address(distributor).balance, 0);
        assertEq(token.balanceOf(address(distributor)), 0);
        assertEq(distributor.unclaimed(recipient), 0);
    }

    // --- AC-6, FR-RESC-001, FR-RESC-003 ------------------------------------------

    function test_ClaimMintsAndLeavesStuckTokensOnDistributor() public {
        vm.prank(owner);
        token.mint(holder, 5 ether);
        vm.prank(holder);
        token.transfer(address(distributor), 5 ether);
        vm.prank(owner);
        distributor.allocate(recipient, 2 ether);

        assertEq(token.balanceOf(address(distributor)), 5 ether);

        vm.prank(recipient);
        distributor.claim();

        assertEq(token.balanceOf(recipient), 2 ether);
        assertEq(token.totalSupply(), 7 ether);
        assertEq(token.balanceOf(address(distributor)), 5 ether);
    }

    // --- AC-7, FR-RESC-003 -------------------------------------------------------

    function test_MintAndAllocateSucceedWithZeroContractEth() public {
        assertEq(address(token).balance, 0);
        assertEq(address(distributor).balance, 0);

        vm.prank(owner);
        token.mint(holder, 1 ether);
        vm.prank(owner);
        distributor.allocate(recipient, 4 ether);

        assertEq(token.balanceOf(holder), 1 ether);
        assertEq(distributor.unclaimed(recipient), 4 ether);
        assertEq(address(token).balance, 0);
        assertEq(address(distributor).balance, 0);
    }
}
