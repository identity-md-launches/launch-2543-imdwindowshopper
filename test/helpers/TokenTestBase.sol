// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Only the Foundry cheatcodes used by this project's tests; no external test dependency.
interface TokenVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address caller) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory logs);
}

abstract contract TokenTestBase {
    TokenVm internal constant vm = TokenVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool value, string memory reason) internal pure {
        require(value, reason);
    }

    function assertEq(uint256 actual, uint256 expected, string memory reason) internal pure {
        require(actual == expected, reason);
    }

    function assertEq(address actual, address expected, string memory reason) internal pure {
        require(actual == expected, reason);
    }

    function assertEq(bytes32 actual, bytes32 expected, string memory reason) internal pure {
        require(actual == expected, reason);
    }

    function assertEq(string memory actual, string memory expected, string memory reason)
        internal
        pure
    {
        require(keccak256(bytes(actual)) == keccak256(bytes(expected)), reason);
    }
}
