// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "src/curve/fallbacks/ConvexImplementation.sol";
import "src/curve/fallbacks/ConvexMinimalProxyFactory.sol";

contract ConvexMinimalProxyTest is Test {
    using FixedPointMathLib for uint256;

    ConvexMinimalProxyFactory public factory;
    ConvexImplementation public implementation;

    ConvexImplementation public cloneFallback;

    //////////////////////////////////////////////////////
    /// --- CONVEX ADDRESSES
    //////////////////////////////////////////////////////

    address public constant BOOSTER = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant REWARD_TOKEN = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant FALLBACK_REWARD_TOKEN = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    uint256 public constant pid = 9;
    ERC20 public constant token = ERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    address public constant BASE_REWARD_POOL = address(0x689440f2Ff927E1f24c72F1087E1FAF471eCe1c8);

    uint256 public constant AMOUNT = 1000 ether;

    function setUp() public {
        vm.rollFork({blockNumber: 18_341_841});

        implementation = new ConvexImplementation();
        factory = new ConvexMinimalProxyFactory(
            BOOSTER, address(this), REWARD_TOKEN, FALLBACK_REWARD_TOKEN, address(implementation)
        );

        cloneFallback = ConvexImplementation(factory.create(pid));

        /// Deal some tokens to the cloneFallback.
        deal(address(token), address(cloneFallback), AMOUNT);
    }

    function test_Implementation() public {
        vm.expectRevert(ConvexImplementation.FACTORY.selector);
        implementation.initialize();

        vm.expectRevert(ConvexImplementation.STRATEGY.selector);
        implementation.deposit(address(0), 0);

        vm.expectRevert(ConvexImplementation.STRATEGY.selector);
        implementation.withdraw(address(0), 0);

        vm.expectRevert(ConvexImplementation.STRATEGY.selector);
        implementation.claim(true, true, address(this));
    }

    function test_Clone() public {
        assertEq(cloneFallback.pid(), pid);
        assertEq(cloneFallback.token(), address(token));
        assertEq(cloneFallback.strategy(), address(this));
        assertEq(cloneFallback.rewardToken(), REWARD_TOKEN);
        assertEq(address(cloneFallback.booster()), BOOSTER);
        assertEq(address(cloneFallback.baseRewardPool()), BASE_REWARD_POOL);
        assertEq(cloneFallback.fallbackRewardToken(), FALLBACK_REWARD_TOKEN);

        /// Assert max allowance given.
        assertEq(token.allowance(address(cloneFallback), address(BOOSTER)), type(uint256).max);
    }

    function test_deposit() public {
        assertEq(token.balanceOf(address(cloneFallback)), AMOUNT);

        /// Deposit 1000 tokens.
        cloneFallback.deposit(address(token), AMOUNT);
        assertEq(token.balanceOf(address(cloneFallback)), 0);

        IBaseRewardPool baseRewardPool = IBaseRewardPool(address(cloneFallback.baseRewardPool()));

        assertEq(cloneFallback.balanceOf(address(token)), AMOUNT);
        assertEq(baseRewardPool.balanceOf(address(cloneFallback)), AMOUNT);
    }

    function test_withdraw() public {
        cloneFallback.deposit(address(token), AMOUNT);

        IBaseRewardPool baseRewardPool = IBaseRewardPool(address(cloneFallback.baseRewardPool()));

        assertEq(cloneFallback.balanceOf(address(token)), AMOUNT);
        assertEq(baseRewardPool.balanceOf(address(cloneFallback)), AMOUNT);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(cloneFallback)), 0);

        cloneFallback.withdraw(address(token), AMOUNT);

        assertEq(token.balanceOf(address(this)), AMOUNT);
        assertEq(token.balanceOf(address(cloneFallback)), 0);
    }

    function test_claimWithoutProtocolFees() public {
        cloneFallback.deposit(address(token), AMOUNT);

        /// Earmark rewards to flow to BaseRewardPool.
        /// We prank to avoid receiving claimIncentive.
        vm.prank(address(0xBEEF));
        IBooster(BOOSTER).earmarkRewards(pid);

        /// Wait 7 days for rewards to accrue.
        skip(7 days);

        IBaseRewardPool baseRewardPool = IBaseRewardPool(address(cloneFallback.baseRewardPool()));

        assertEq(cloneFallback.balanceOf(address(token)), AMOUNT);
        assertEq(baseRewardPool.balanceOf(address(cloneFallback)), AMOUNT);

        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(this)), 0);
        assertEq(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(this)), 0);

        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(cloneFallback)), 0);
        assertEq(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(cloneFallback)), 0);

        (,, uint256 protocolFees) = cloneFallback.claim(false, true, address(this));

        assertGt(ERC20(REWARD_TOKEN).balanceOf(address(this)), 0);
        assertGt(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(this)), 0);

        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(cloneFallback)), 0);
        assertEq(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(cloneFallback)), 0);

        /// Check correct accounting.
        assertEq(protocolFees, 0);
    }

    function test_claimWithProtocolFees() public {
        cloneFallback.deposit(address(token), AMOUNT);

        /// Earmark rewards to flow to BaseRewardPool.
        /// We prank to avoid receiving claimIncentive.
        vm.prank(address(0xBEEF));
        IBooster(BOOSTER).earmarkRewards(pid);

        /// Wait 7 days for rewards to accrue.
        skip(7 days);

        IBaseRewardPool baseRewardPool = IBaseRewardPool(address(cloneFallback.baseRewardPool()));

        assertEq(cloneFallback.balanceOf(address(token)), AMOUNT);
        assertEq(baseRewardPool.balanceOf(address(cloneFallback)), AMOUNT);

        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(this)), 0);
        assertEq(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(this)), 0);

        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(cloneFallback)), 0);
        assertEq(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(cloneFallback)), 0);

        /// Set protocol fees to 10%.
        factory.updateProtocolFee(1000);

        (,, uint256 protocolFees) = cloneFallback.claim(false, true, address(this));

        assertGt(ERC20(REWARD_TOKEN).balanceOf(address(this)), 0);
        assertGt(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(this)), 0);

        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(cloneFallback)), 0);
        assertEq(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(cloneFallback)), 0);

        /// Check correct accounting.
        assertEq(protocolFees, ERC20(REWARD_TOKEN).balanceOf(address(this)).mulDiv(1_000, 10_000));
    }

    function test_externalClaim() public {
        cloneFallback.deposit(address(token), AMOUNT);

        /// Earmark rewards to flow to BaseRewardPool.
        /// We prank to avoid receiving claimIncentive.
        vm.prank(address(0xBEEF));
        IBooster(BOOSTER).earmarkRewards(pid);

        /// Wait 7 days for rewards to accrue.
        skip(7 days);

        IBaseRewardPool baseRewardPool = IBaseRewardPool(address(cloneFallback.baseRewardPool()));

        assertEq(cloneFallback.balanceOf(address(token)), AMOUNT);
        assertEq(baseRewardPool.balanceOf(address(cloneFallback)), AMOUNT);

        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(this)), 0);
        assertEq(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(this)), 0);

        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(cloneFallback)), 0);
        assertEq(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(cloneFallback)), 0);

        /// Set protocol fees to 10%.
        factory.updateProtocolFee(1000);

        /// We claim trough Convex directly.
        IBaseRewardPool(address(cloneFallback.baseRewardPool())).getReward(address(cloneFallback), false);

        /// Then we trigger claim to collect from the fallback.
        /// It should give the same result as the previous test.
        (,, uint256 protocolFees) = cloneFallback.claim(false, true, address(this));

        assertGt(ERC20(REWARD_TOKEN).balanceOf(address(this)), 0);
        assertGt(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(this)), 0);

        assertEq(ERC20(REWARD_TOKEN).balanceOf(address(cloneFallback)), 0);
        assertEq(ERC20(FALLBACK_REWARD_TOKEN).balanceOf(address(cloneFallback)), 0);

        /// Check correct accounting.
        assertEq(protocolFees, ERC20(REWARD_TOKEN).balanceOf(address(this)).mulDiv(1_000, 10_000));
    }
}
