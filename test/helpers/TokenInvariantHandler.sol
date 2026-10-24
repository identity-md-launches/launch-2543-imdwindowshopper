// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDwindowshopper} from "../../src/IMDwindowshopper.sol";
import {TokenPropertyBase} from "./TokenPropertyBase.sol";

/// @dev A closed set of four holders. Only these holders send, receive, and approve;
/// no token storage is patched, and the token contract is never impersonated.
contract TokenInvariantHandler is TokenPropertyBase {
    IMDwindowshopper public immutable token;
    address[4] public actors;

    // These records come only from requested successful operations, never balanceOf/allowance.
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public calls;
    uint256 public positiveTransfers;
    uint256 public positiveDelegatedTransfers;
    uint256 public rejectedCalls;

    constructor(IMDwindowshopper token_, address deployer) {
        token = token_;
        actors = [deployer, address(0xA11CE), address(0xB0B), address(0xCA401)];
    }

    function expectedBalance(address actor) public view returns (uint256) {
        return EXPECTED_SUPPLY / 4 + received[actor] - sent[actor];
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _edgeAmount(amountSeed, expectedBalance(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid transfer returned false");
        _recordMovement(from, to, amount);
        if (amount > 0 && from != to) ++positiveTransfers;
        ++calls;
    }

    /// @dev Zero revokes, max grants unlimited access, and the other modes cover
    /// finite allowances both within and far above the total token supply.
    function approve(uint8 ownerSeed, uint8 spenderSeed, uint8 mode, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount;
        if (mode % 4 == 1) amount = type(uint256).max;
        else if (mode % 4 == 2) amount = bound(amountSeed, 0, EXPECTED_SUPPLY);
        else if (mode % 4 == 3) amount = amountSeed;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval returned false");
        expectedAllowance[owner][spender] = amount;
        ++calls;
    }

    /// @dev Uses approvals left by earlier random calls; it does not silently grant
    /// a new approval before spending. Owner, spender, and recipient may coincide.
    function transferFrom(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amountSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance(owner);
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 limit = balance < allowance ? balance : allowance;
        uint256 amount = _edgeAmount(amountSeed, limit);
        _spend(owner, spender, to, amount);
        ++calls;
    }

    /// @dev Unbounded amounts explore both errors and successes, including max uint256.
    /// An expected failure leaves the independent movement/allowance records untouched.
    function transferFromRaw(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amount)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance(owner);
        if (amount > allowance) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount
                )
            );
        } else if (amount > balance) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount
                )
            );
        } else {
            _spend(owner, spender, to, amount);
            ++calls;
            return;
        }
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
        ++rejectedCalls;
        ++calls;
    }

    function rejectOverBalance(uint8 fromSeed, uint8 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance(from);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount
            )
        );
        vm.prank(from);
        token.transfer(to, amount);
        ++rejectedCalls;
        ++calls;
    }

    function rejectZeroRecipient(
        uint8 ownerSeed,
        uint8 spenderSeed,
        uint256 amountSeed,
        bool delegated
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 limit = expectedBalance(owner);
        if (delegated && expectedAllowance[owner][spender] < limit) {
            limit = expectedAllowance[owner][spender];
        }
        uint256 amount = _edgeAmount(amountSeed, limit);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
        ++rejectedCalls;
        ++calls;
    }

    function rejectZeroSpender(uint8 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        vm.prank(owner);
        token.approve(address(0), amount);
        ++rejectedCalls;
        ++calls;
    }

    function _spend(address owner, address spender, address to, uint256 amount) private {
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "valid delegated transfer returned false");
        if (expectedAllowance[owner][spender] != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        _recordMovement(owner, to, amount);
        if (amount > 0 && owner != to) ++positiveDelegatedTransfers;
    }

    function _recordMovement(address from, address to, uint256 amount) private {
        sent[from] += amount;
        received[to] += amount;
    }

    function _actor(uint8 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Deliberately exercises zero, one base unit, the whole available amount,
    /// and interior values instead of hoping uniform random inputs reach the edges.
    function _edgeAmount(uint256 seed, uint256 maximum) private pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return maximum == 0 ? 0 : 1;
        if (seed % 4 == 2) return maximum;
        return bound(seed, 0, maximum);
    }
}
