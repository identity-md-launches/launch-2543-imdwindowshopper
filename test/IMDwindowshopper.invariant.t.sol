// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IMDwindowshopper} from "../src/IMDwindowshopper.sol";
import {TokenPropertyBase} from "./helpers/TokenPropertyBase.sol";
import {TokenInvariantHandler} from "./helpers/TokenInvariantHandler.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract IMDwindowshopperInvariantTest is TokenPropertyBase {
    IMDwindowshopper internal token;
    TokenInvariantHandler internal handler;

    // Foundry's targeting ABI, kept local so no new dependency or remapping is needed.
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function setUp() public {
        token = new IMDwindowshopper();
        handler = new TokenInvariantHandler(token, address(this));
        for (uint256 i = 1; i < 4; ++i) {
            assertTrue(
                token.transfer(handler.actors(i), EXPECTED_SUPPLY / 4),
                "initial distribution failed"
            );
        }
        invariant_BalancesMatchAuthorizedMovements();
    }

    function targetContracts() external view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() external view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.transferFromRaw.selector;
        selectors[4] = handler.rejectOverBalance.selector;
        selectors[5] = handler.rejectZeroRecipient.selector;
        selectors[6] = handler.rejectZeroSpender.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    function invariant_FixedSupplyAndConservation() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY, "supply changed after constructor");
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, EXPECTED_SUPPLY, "tokens created, destroyed, or diverted outside holders");
        assertEq(token.balanceOf(address(0)), 0, "zero address acquired tokens");
        assertEq(token.balanceOf(address(token)), 0, "token retained an unauthorized fee");
        assertEq(token.balanceOf(address(handler)), 0, "handler acquired an unauthorized balance");
    }

    function invariant_BalancesMatchAuthorizedMovements() public view {
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(
                token.balanceOf(actor) + handler.sent(actor),
                EXPECTED_SUPPLY / 4 + handler.received(actor),
                "holder balance does not match authorized inflows and outflows"
            );
        }
    }

    function invariant_AllowancesMatchApprovalsAndSuccessfulSpends() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "approval overwrite, revocation, spend, or rollback changed allowance incorrectly"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0, "zero spender obtained an allowance");
        }
    }

    function invariant_MetadataIsStable() public view {
        assertEq(token.name(), "IMDwindowshopper", "name changed");
        assertEq(token.symbol(), "WWW", "symbol changed");
        assertEq(token.decimals(), 18, "decimals changed");
    }

    function afterInvariant() public view {
        assertTrue(handler.calls() > 0, "invariant runner did not exercise the handler");
    }

    /// @dev Pins a useful sequence and demonstrates each random action is reachable.
    /// In particular, successful delegated transfers must not be lost among reverts.
    function test_HandlerExercisesTransfersRevocationsAndFailures() public {
        handler.transfer(0, 1, 1);
        handler.approve(1, 2, 2, 100);
        handler.transferFrom(1, 2, 3, 1);
        handler.transferFromRaw(1, 2, 3, 99);
        handler.transferFromRaw(1, 2, 3, 1); // Exhausted allowance.
        handler.approve(1, 2, 1, 0); // Unlimited allowance.
        handler.transferFrom(1, 2, 1, 2); // Delegated self-transfer of the whole balance.
        handler.transferFromRaw(1, 2, 3, type(uint256).max); // Balance failure with unlimited allowance.
        handler.rejectZeroRecipient(1, 2, 1, true);
        handler.approve(1, 2, 0, 0); // Revoke unlimited allowance.
        handler.transferFromRaw(1, 2, 3, 1);
        handler.rejectOverBalance(3, 3, type(uint256).max);
        handler.rejectZeroRecipient(0, 2, 0, false);
        handler.rejectZeroSpender(0, type(uint256).max);

        assertEq(handler.calls(), 14, "some handler actions did not execute");
        assertEq(handler.positiveTransfers(), 1, "no positive direct transfer");
        assertEq(handler.positiveDelegatedTransfers(), 2, "no positive delegated transfer");
        assertEq(handler.rejectedCalls(), 7, "failure paths were not exercised");
        invariant_FixedSupplyAndConservation();
        invariant_BalancesMatchAuthorizedMovements();
        invariant_AllowancesMatchApprovalsAndSuccessfulSpends();
        invariant_MetadataIsStable();
    }
}
