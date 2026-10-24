// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TokenTestBase} from "./TokenTestBase.sol";

/// @dev Keeps the new tests dependency-free, like the existing test suite.
abstract contract TokenPropertyBase is TokenTestBase {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 * 1e18;

    /// @dev Inclusive bounds, preserving inputs already in range, without discarded fuzz cases.
    function bound(uint256 value, uint256 minimum, uint256 maximum)
        internal
        pure
        returns (uint256)
    {
        require(minimum <= maximum, "invalid test bounds");
        if (value >= minimum && value <= maximum) return value;
        return minimum + value % (maximum - minimum + 1);
    }
}
