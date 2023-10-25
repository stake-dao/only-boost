// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "src/fallbacks/convex/ConvexImplementation.sol";
import "src/fallbacks/convex/ConvexMinimalProxyFactory.sol";

contract PoolFactoryTest is Test {
    using FixedPointMathLib for uint256;

    function setUp() public {
        vm.rollFork({blockNumber: 18_341_841});
    }
}
