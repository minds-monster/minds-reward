// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {RewardToken} from "../contracts/RewardToken.sol";

/// @dev FEAT-003: ERC-20 conformance while unpaused (NFR-MNT-003). Minting lives in
///      RewardToken.t.sol; pause lives in Pause.t.sol.
contract RewardTokenConformanceTest is Test {
    RewardToken internal token;

    address internal owner;
    address internal holder;
    address internal recipient;
    address internal spender;
    address internal stranger;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        owner = makeAddr("owner");
        holder = makeAddr("holder");
        recipient = makeAddr("recipient");
        spender = makeAddr("spender");
        stranger = makeAddr("stranger");

        token = new RewardToken("Reward Token", "RWD", owner);
    }

    function _mintToHolder(uint256 amount) internal {
        vm.prank(owner);
        token.mint(holder, amount);
    }

    // --- AC-1, FR-TOK-001, FR-TOK-002, UC-16 -------------------------------------

    function test_NameAndSymbolMatchConstructor() public view {
        assertEq(token.name(), "Reward Token");
        assertEq(token.symbol(), "RWD");
    }

    function test_NameAndSymbolComeFromConstructorArguments() public {
        RewardToken other = new RewardToken("Other Token", "OTH", owner);
        assertEq(other.name(), "Other Token");
        assertEq(other.symbol(), "OTH");
    }

    // --- AC-2, FR-ERC-001, FR-ERC-002, FR-EXT-001, UC-16 --------------------------

    function test_DecimalsIs18UnknownBalanceIsZeroSupplyTracksMintNotTransfer() public {
        assertEq(token.decimals(), 18);
        assertEq(token.balanceOf(stranger), 0);
        assertEq(token.totalSupply(), 0);

        _mintToHolder(10 ether);
        assertEq(token.totalSupply(), 10 ether);
        assertEq(token.balanceOf(holder), 10 ether);

        vm.prank(holder);
        token.transfer(recipient, 4 ether);

        assertEq(token.totalSupply(), 10 ether);
        assertEq(token.balanceOf(holder), 6 ether);
        assertEq(token.balanceOf(recipient), 4 ether);
    }

    // --- AC-4, FR-ERC-003, FR-ERC-007, FR-ERC-016, UC-13 --------------------------

    function test_TransferMovesExactAmountEmitsTransferAndReturnsTrue() public {
        _mintToHolder(5 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, recipient, 3 ether);

        vm.prank(holder);
        bool ok = token.transfer(recipient, 3 ether);
        assertTrue(ok);

        assertEq(token.balanceOf(holder), 2 ether);
        assertEq(token.balanceOf(recipient), 3 ether);
        assertEq(token.totalSupply(), 5 ether);
    }

    // --- AC-5, FR-ERC-013, UC-13 1b, NFR-MNT-003 ---------------------------------

    function test_ZeroValueTransferSucceedsEmitsAndLeavesBalances() public {
        _mintToHolder(5 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, recipient, 0);

        vm.prank(holder);
        bool ok = token.transfer(recipient, 0);
        assertTrue(ok);

        assertEq(token.balanceOf(holder), 5 ether);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), 5 ether);
    }

    // --- AC-6, FR-ERC-014, UC-13 1c, NFR-MNT-003 ---------------------------------

    function test_SelfTransferLeavesBalanceUnchangedAndEmits() public {
        _mintToHolder(5 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, holder, 2 ether);

        vm.prank(holder);
        bool ok = token.transfer(holder, 2 ether);
        assertTrue(ok);

        assertEq(token.balanceOf(holder), 5 ether);
        assertEq(token.totalSupply(), 5 ether);
    }

    // --- AC-7, FR-ERC-009, UC-13 2a ----------------------------------------------

    function test_TransferAboveBalanceRevertsInsufficientBalance() public {
        _mintToHolder(1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1 ether, 2 ether)
        );
        vm.prank(holder);
        token.transfer(recipient, 2 ether);

        assertEq(token.balanceOf(holder), 1 ether);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), 1 ether);
    }

    // --- AC-8, FR-ERC-011, UC-13 1d, NFR-MNT-003 ---------------------------------

    function test_TransferToZeroRevertsInvalidReceiver() public {
        _mintToHolder(1 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(holder);
        token.transfer(address(0), 1 ether);

        assertEq(token.balanceOf(holder), 1 ether);
        assertEq(token.totalSupply(), 1 ether);
    }

    function test_TransferFromToZeroRevertsInvalidReceiver() public {
        _mintToHolder(1 ether);
        vm.prank(holder);
        token.approve(spender, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 1 ether);

        assertEq(token.balanceOf(holder), 1 ether);
        assertEq(token.allowance(holder, spender), 1 ether);
        assertEq(token.totalSupply(), 1 ether);
    }

    // --- AC-16, NFR-MNT-003 mint Transfer ----------------------------------------

    function test_MintEmitsTransferFromZero() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(0), holder, 7 ether);

        vm.prank(owner);
        token.mint(holder, 7 ether);

        assertEq(token.balanceOf(holder), 7 ether);
        assertEq(token.totalSupply(), 7 ether);
    }

    // --- AC-9, FR-ERC-004, FR-ERC-005, FR-ERC-008, UC-14, NFR-MNT-003 overwrite --

    function test_ApproveSetsAllowanceEmitsAndOverwrites() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(holder, spender, 10 ether);

        vm.prank(holder);
        bool first = token.approve(spender, 10 ether);
        assertTrue(first);
        assertEq(token.allowance(holder, spender), 10 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(holder, spender, 4 ether);

        vm.prank(holder);
        bool second = token.approve(spender, 4 ether);
        assertTrue(second);
        assertEq(token.allowance(holder, spender), 4 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(holder, spender, 0);

        vm.prank(holder);
        bool revoked = token.approve(spender, 0);
        assertTrue(revoked);
        assertEq(token.allowance(holder, spender), 0);
    }

    // --- AC-10, FR-ERC-012, UC-14 1d ---------------------------------------------

    function test_ApproveZeroSpenderRevertsInvalidSpender() public {
        vm.prank(holder);
        token.approve(spender, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 1 ether);

        assertEq(token.allowance(holder, spender), 1 ether);
        assertEq(token.allowance(holder, address(0)), 0);
    }

    // --- AC-11, FR-ERC-006, FR-ERC-007, FR-ERC-016, UC-13 1a ----------------------

    function test_TransferFromMovesAmountReducesFiniteAllowanceAndEmits() public {
        _mintToHolder(10 ether);
        vm.prank(holder);
        token.approve(spender, 7 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, recipient, 3 ether);

        vm.prank(spender);
        bool ok = token.transferFrom(holder, recipient, 3 ether);
        assertTrue(ok);

        assertEq(token.balanceOf(holder), 7 ether);
        assertEq(token.balanceOf(recipient), 3 ether);
        assertEq(token.allowance(holder, spender), 4 ether);
        assertEq(token.totalSupply(), 10 ether);
    }

    // --- AC-12, FR-ERC-010, UC-13 1f ---------------------------------------------

    function test_TransferFromAboveAllowanceRevertsAndLeavesState() public {
        _mintToHolder(10 ether);
        vm.prank(holder);
        token.approve(spender, 2 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                spender,
                2 ether,
                3 ether
            )
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, 3 ether);

        assertEq(token.balanceOf(holder), 10 ether);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), 2 ether);
        assertEq(token.totalSupply(), 10 ether);
    }

    function test_TransferFromAboveBalanceWithSufficientAllowanceReverts() public {
        _mintToHolder(1 ether);
        vm.prank(holder);
        token.approve(spender, 5 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1 ether, 2 ether)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, 2 ether);

        assertEq(token.balanceOf(holder), 1 ether);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), 5 ether);
    }

    // --- AC-13, FR-ERC-015, UC-14 1a, NFR-MNT-003 --------------------------------

    function test_MaxUintAllowanceIsUnlimitedAndNotDecreased() public {
        _mintToHolder(5 ether);
        vm.prank(holder);
        token.approve(spender, type(uint256).max);
        assertEq(token.allowance(holder, spender), type(uint256).max);

        vm.prank(spender);
        token.transferFrom(holder, recipient, 2 ether);

        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), 3 ether);
        assertEq(token.balanceOf(recipient), 2 ether);
    }

    // --- AC-3, FR-TOK-005 --------------------------------------------------------

    function test_MetadataUnchangedAfterMintTransferApproveAndPauseCycle() public {
        string memory nameBefore = token.name();
        string memory symbolBefore = token.symbol();
        uint8 decimalsBefore = token.decimals();

        _mintToHolder(5 ether);
        vm.prank(holder);
        token.transfer(recipient, 1 ether);
        vm.prank(holder);
        token.approve(spender, 1 ether);
        vm.prank(owner);
        token.pause();
        vm.prank(owner);
        token.unpause();

        assertEq(token.name(), nameBefore);
        assertEq(token.symbol(), symbolBefore);
        assertEq(token.decimals(), decimalsBefore);
        assertEq(nameBefore, "Reward Token");
        assertEq(symbolBefore, "RWD");
        assertEq(decimalsBefore, 18);
    }

    // --- AC-14, FR-ERC-017 -------------------------------------------------------

    function test_TransferToRevertingRecipientSucceedsWithoutCallback() public {
        RevertingRecipient hook = new RevertingRecipient();
        _mintToHolder(5 ether);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, address(hook), 2 ether);

        vm.prank(holder);
        bool ok = token.transfer(address(hook), 2 ether);
        assertTrue(ok);

        assertEq(token.balanceOf(address(hook)), 2 ether);
        assertEq(token.balanceOf(holder), 3 ether);
    }
}

/// @dev Recipient that reverts on every callback a hooked token might invoke (AC-14).
contract RevertingRecipient {
    error HookCalled();

    receive() external payable {
        revert HookCalled();
    }

    fallback() external payable {
        revert HookCalled();
    }

    function tokensReceived(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external pure {
        revert HookCalled();
    }

    function onTransferReceived(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        revert HookCalled();
    }
}
