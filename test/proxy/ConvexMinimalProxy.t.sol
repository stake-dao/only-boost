// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {ConvexImplementation} from "src/v2/fallbacks/convex/ConvexImplementation.sol";
import {ConvexMinimalProxyFactory} from "src/v2/fallbacks/convex/ConvexMinimalProxyFactory.sol";

contract ConvexMinimalProxyTest is Test {
    ConvexMinimalProxyFactory public factory;
    ConvexImplementation public implementation;

    function setUp() public {
        implementation = new ConvexImplementation();
        factory = new ConvexMinimalProxyFactory(address(implementation));
    }

    function test_Clone() public {
        address token = address(0x1);
        address rewardToken = address(0x2);
        address fallbackRewardToken = address(0x3);
        address strategy = address(0x4);
        address booster = address(0x5);
        address baseRewardPool = address(0x6);
        uint256 pid = 1;

        ConvexImplementation convexFallback = ConvexImplementation(
            factory.create(token, rewardToken, fallbackRewardToken, strategy, booster, baseRewardPool, pid)
        );

        assertEq(convexFallback.pid(), pid);
        assertEq(convexFallback.token(), token);
        assertEq(convexFallback.booster(), booster);
        assertEq(convexFallback.strategy(), strategy);
        assertEq(convexFallback.rewardToken(), rewardToken);
        assertEq(convexFallback.baseRewardPool(), baseRewardPool);
        assertEq(convexFallback.fallbackRewardToken(), fallbackRewardToken);
    }
}
