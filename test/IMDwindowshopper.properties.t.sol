// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDwindowshopper} from "../src/IMDwindowshopper.sol";
import {TokenPropertyBase} from "./helpers/TokenPropertyBase.sol";

/// forge-config: default.fuzz.runs = 1000
contract IMDwindowshopperPropertiesTest is TokenPropertyBase {
    IMDwindowshopper internal token;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    function setUp() public {
        token = new IMDwindowshopper();
    }

    function test_OneBaseUnitCanMoveAndReturnThroughDelegatedTransfer() public {
        assertTrue(token.transfer(ALICE, 1), "one-unit transfer failed");
        vm.prank(ALICE);
        assertTrue(token.transfer(ALICE, 1), "one-unit self-transfer failed");
        assertEq(token.balanceOf(ALICE), 1, "self-transfer changed balance");
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 1), "one-unit approval failed");
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, address(this), 1), "one-unit return failed");
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY, "one-unit round trip lost value");
        assertEq(token.balanceOf(ALICE), 0, "sender retained the unit");
        assertEq(token.allowance(ALICE, SPENDER), 0, "one-unit allowance not consumed");
    }

    function test_MaximumTransferAmountRevertsWithoutWrappingBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                EXPECTED_SUPPLY,
                type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(
            token.balanceOf(address(this)),
            EXPECTED_SUPPLY,
            "failed maximum transfer debited sender"
        );
        assertEq(token.balanceOf(ALICE), 0, "failed maximum transfer credited recipient");
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "failed maximum transfer changed supply");
    }

    function test_MaximumDelegatedAmountCannotSpendBeyondBalance() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                EXPECTED_SUPPLY,
                type(uint256).max
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(
            token.allowance(address(this), SPENDER),
            type(uint256).max,
            "failure changed unlimited allowance"
        );
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY, "failure moved holder balance");
        assertEq(token.balanceOf(ALICE), 0, "failure credited recipient");
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "failure changed supply");
    }

    function test_MaximumMinusOneAllowanceRemainsFinite() public {
        token.approve(SPENDER, type(uint256).max);
        token.approve(SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(
            token.transferFrom(address(this), ALICE, EXPECTED_SUPPLY), "full-supply spend failed"
        );
        assertEq(
            token.allowance(address(this), SPENDER),
            type(uint256).max - 1 - EXPECTED_SUPPLY,
            "near-maximum finite allowance was treated as unlimited"
        );
        assertEq(token.balanceOf(address(this)), 0, "holder retained spent balance");
        assertEq(token.balanceOf(ALICE), EXPECTED_SUPPLY, "recipient did not receive full supply");
    }

    function test_UnlimitedApprovalCanBeRevokedAfterUse() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1), "initial authorized spend failed");
        token.approve(SPENDER, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0, "revoked unlimited approval persisted");
        assertEq(token.balanceOf(ALICE), 1, "revoked spender moved more tokens");
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY - 1, "revoked spend debited owner");
    }

    function test_ZeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0, "zero spender acquired approval");
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY, "invalid approval moved tokens");
    }

    function test_DelegatedSelfTransferCannotBypassBalanceCheck() public {
        token.approve(SPENDER, EXPECTED_SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                EXPECTED_SUPPLY,
                EXPECTED_SUPPLY + 1
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(this), EXPECTED_SUPPLY + 1);
        assertEq(
            token.allowance(address(this), SPENDER),
            EXPECTED_SUPPLY + 1,
            "failure consumed allowance"
        );
        assertEq(
            token.balanceOf(address(this)), EXPECTED_SUPPLY, "failed self-transfer changed balance"
        );
    }

    function test_SelfApprovalAllowsOwnerToUseTransferFrom() public {
        token.approve(address(this), 2);
        assertTrue(token.transferFrom(address(this), ALICE, 1), "self-approved spend failed");
        assertTrue(
            token.transferFrom(address(this), address(this), 1),
            "self-approved self-transfer failed"
        );
        assertEq(token.allowance(address(this), address(this)), 0, "self-approval was not consumed");
        assertEq(token.balanceOf(ALICE), 1, "self-approved spend did not arrive");
        assertEq(
            token.balanceOf(address(this)), EXPECTED_SUPPLY - 1, "self-transfer changed balance"
        );
    }

    function test_TokenContractCanReceiveTransfersWithoutChangingSupply() public {
        assertTrue(token.transfer(address(token), 1), "contract recipient rejected transfer");
        token.approve(SPENDER, EXPECTED_SUPPLY - 1);
        vm.prank(SPENDER);
        assertTrue(
            token.transferFrom(address(this), address(token), EXPECTED_SUPPLY - 1),
            "contract recipient rejected delegated transfer"
        );
        assertEq(token.balanceOf(address(token)), EXPECTED_SUPPLY, "contract recipient was shorted");
        assertEq(token.balanceOf(address(this)), 0, "sender retained transferred tokens");
        assertEq(token.allowance(address(this), SPENDER), 0, "allowance not consumed");
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "contract transfer changed supply");
    }

    function testFuzz_TransferRoundTripRestoresEveryBalance(uint256 balanceSeed, uint256 amountSeed)
        public
    {
        uint256 balance = bound(balanceSeed, 0, EXPECTED_SUPPLY);
        uint256 amount = bound(amountSeed, 0, balance);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount), "outbound transfer failed");
        assertEq(token.balanceOf(ALICE), balance - amount, "outbound sender delta incorrect");
        assertEq(token.balanceOf(BOB), amount, "outbound recipient delta incorrect");
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, amount), "return transfer failed");
        assertEq(token.balanceOf(ALICE), balance, "round trip changed sender balance");
        assertEq(token.balanceOf(BOB), 0, "round trip left recipient value");
        assertEq(
            token.balanceOf(address(this)),
            EXPECTED_SUPPLY - balance,
            "round trip affected bystander"
        );
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "round trip changed supply");
    }

    function testFuzz_ApprovalReplacementIsIdempotentAndIsolated(uint256 first, uint256 replacement)
        public
    {
        token.approve(SPENDER, first);
        token.approve(BOB, first);
        vm.prank(ALICE);
        token.approve(SPENDER, first);
        token.approve(SPENDER, replacement);
        assertEq(
            token.allowance(address(this), SPENDER),
            replacement,
            "approval did not replace old value"
        );
        token.approve(SPENDER, replacement);
        assertEq(
            token.allowance(address(this), SPENDER),
            replacement,
            "repeated approval accumulated value"
        );
        assertEq(token.allowance(address(this), BOB), first, "another spender's allowance changed");
        assertEq(token.allowance(ALICE, SPENDER), first, "another owner's allowance changed");
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY, "approval moved holder tokens");
        assertEq(token.balanceOf(ALICE), 0, "approval funded empty owner");
        assertEq(token.balanceOf(SPENDER), 0, "approval funded spender");
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "approval changed supply");
    }

    function testFuzz_FiniteAllowanceAboveSupplyIsConsumedExactly(
        uint256 allowanceSeed,
        uint256 amountSeed
    ) public {
        uint256 approved = bound(allowanceSeed, EXPECTED_SUPPLY + 1, type(uint256).max - 1);
        uint256 amount = bound(amountSeed, 1, EXPECTED_SUPPLY);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(
            token.transferFrom(address(this), BOB, amount), "large finite allowance spend failed"
        );
        assertEq(
            token.allowance(address(this), SPENDER),
            approved - amount,
            "finite allowance not consumed exactly"
        );
        assertEq(token.balanceOf(BOB), amount, "delegated transfer was shorted");
        assertEq(token.balanceOf(address(this)), EXPECTED_SUPPLY - amount, "wrong holder debit");
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "large allowance spend changed supply");
    }

    function testFuzz_FailedBalanceCheckPreservesApprovalForLaterFunding(
        uint256 balanceSeed,
        uint256 extraSeed
    ) public {
        uint256 balance = bound(balanceSeed, 0, EXPECTED_SUPPLY - 1);
        uint256 extra = bound(extraSeed, 1, EXPECTED_SUPPLY - balance);
        uint256 amount = balance + extra;
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(SPENDER, amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), amount, "failed transfer consumed approval");
        assertEq(token.balanceOf(ALICE), balance, "failed transfer debited owner");
        assertEq(token.balanceOf(BOB), 0, "failed transfer credited recipient");

        token.transfer(ALICE, extra);
        vm.prank(SPENDER);
        assertTrue(
            token.transferFrom(ALICE, BOB, amount),
            "unchanged approval could not be used after funding"
        );
        assertEq(token.allowance(ALICE, SPENDER), 0, "successful retry did not exhaust approval");
        assertEq(token.balanceOf(ALICE), 0, "successful retry did not empty holder");
        assertEq(token.balanceOf(BOB), amount, "successful retry arrived short");
        assertEq(
            token.balanceOf(address(this)), EXPECTED_SUPPLY - amount, "funding debited wrong amount"
        );
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "failed or retried spend changed supply");
    }

    function testFuzz_InvalidRecipientPreservesFiniteOrUnlimitedApproval(
        uint256 amountSeed,
        bool unlimited
    ) public {
        uint256 amount = bound(amountSeed, 0, EXPECTED_SUPPLY);
        uint256 approval = unlimited ? type(uint256).max : amount;
        token.approve(SPENDER, approval);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), amount);
        assertEq(
            token.allowance(address(this), SPENDER), approval, "invalid recipient consumed approval"
        );
        assertEq(
            token.balanceOf(address(this)), EXPECTED_SUPPLY, "invalid recipient debited holder"
        );
        assertEq(token.balanceOf(address(0)), 0, "invalid recipient received tokens");

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, amount), "valid retry failed");
        assertEq(
            token.allowance(address(this), SPENDER),
            unlimited ? approval : 0,
            "wrong allowance after retry"
        );
        assertEq(token.balanceOf(BOB), amount, "valid retry arrived short");
        assertEq(
            token.balanceOf(address(this)),
            EXPECTED_SUPPLY - amount,
            "valid retry debited wrong amount"
        );
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "invalid recipient or retry changed supply");
    }

    function testFuzz_DelegatedSelfTransferSpendsOnlyAllowance(uint256 amountSeed, bool unlimited)
        public
    {
        uint256 amount = bound(amountSeed, 0, EXPECTED_SUPPLY);
        uint256 approval = unlimited ? type(uint256).max : amount;
        token.approve(SPENDER, approval);
        vm.prank(SPENDER);
        assertTrue(
            token.transferFrom(address(this), address(this), amount),
            "delegated self-transfer failed"
        );
        assertEq(
            token.balanceOf(address(this)),
            EXPECTED_SUPPLY,
            "delegated self-transfer changed balance"
        );
        assertEq(
            token.allowance(address(this), SPENDER),
            unlimited ? approval : 0,
            "wrong self-transfer allowance"
        );
        assertEq(token.balanceOf(SPENDER), 0, "delegated self-transfer paid spender");
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "delegated self-transfer changed supply");
    }
}
