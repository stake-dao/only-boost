// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {ILocker} from "src/interfaces/ILocker.sol";
import {CRVStrategy} from "src/v2/CRVStrategy.sol";
import "src/v2/fallbacks/convex/ConvexImplementation.sol";
import "src/v2/fallbacks/convex/ConvexMinimalProxyFactory.sol";
import {Optimizer} from "src/v2/only-boost-helper/Optimizer.sol";

import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {LiquidityGaugeMock} from "test/mocks/LiquidityGaugeMock.sol";

contract OnlyBoostTest is Test {
    using FixedPointMathLib for uint256;

    ILocker public locker;
    Optimizer public optimizer;
    CRVStrategy public strategy;

    ConvexMinimalProxyFactory public factory;
    ConvexImplementation public implementation;

    LiquidityGaugeMock public mockLiquidityGauge;

    ConvexImplementation public cloneFallback;

    //////////////////////////////////////////////////////
    /// --- CONVEX ADDRESSES
    //////////////////////////////////////////////////////

    address public constant BOOSTER = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant REWARD_TOKEN = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant FALLBACK_REWARD_TOKEN = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    uint256 public constant pid = 9;
    ERC20 public constant token = ERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    address public constant gauge = address(0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A);
    address public constant rewardDistributor = address(0xf99FD99711671268EE557fEd651EA45e34B2414f);

    uint256 public constant AMOUNT = 100_000 ether;

    address public constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6; // StakeDAO CRV Locker
    address public constant VE_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2; // veCRV
    address public constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0; // Convex Minter

    function setUp() public {
        vm.rollFork({blockNumber: 17_700_000});

        /// Initialize Locker
        locker = ILocker(LOCKER);

        strategy = new CRVStrategy(
            address(this),
            LOCKER,
            VE_CRV,
            REWARD_TOKEN,
            MINTER
        );

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(payable(address(strategy)));

        implementation = new ConvexImplementation();
        factory =
        new ConvexMinimalProxyFactory(BOOSTER, address(strategy), REWARD_TOKEN, FALLBACK_REWARD_TOKEN, address(implementation));

        optimizer = new Optimizer(address(strategy), address(factory));
        strategy.setOptimizer(address(optimizer));

        /// Act as a vault.
        strategy.toggleVault(address(this));

        cloneFallback = ConvexImplementation(factory.create(address(token), pid));

        /// Deal some tokens to the cloneFallback.
        deal(address(token), address(this), AMOUNT);

        token.approve(address(strategy), type(uint256).max);
        strategy.setGauge(address(token), address(gauge));

        strategy.setRewardDistributor(address(gauge), address(rewardDistributor));

        vm.startPrank(ILiquidityGauge(address(rewardDistributor)).admin());
        /// Update the rewardToken distributor to the strategy.
        ILiquidityGauge(address(rewardDistributor)).set_reward_distributor(REWARD_TOKEN, address(strategy));

        // ILiquidityGauge(address(rewardDistributor)).set_reward_distributor(EXTRA_REWARD_TOKEN_1, address(strategy));

        /// Transfer Ownership of the gauge to the strategy.
        ILiquidityGauge(address(rewardDistributor)).commit_transfer_ownership(address(strategy));

        vm.stopPrank();
        /// Accept ownership of the gauge.
        strategy.execute(address(rewardDistributor), 0, abi.encodeWithSignature("accept_transfer_ownership()"));

        /// Add the reward token to the rewardDistributor.
        strategy.setLGtype(gauge, 1);
        strategy.addRewardToken(gauge, FALLBACK_REWARD_TOKEN);
        // strategy.addRewardToken(gauge, EXTRA_REWARD_TOKEN_2);

        /// We need to overwrite the locker balance.
        deal(address(gauge), address(locker), 0);
    }

    function test_deposit() public {
        /// Deposit 1000 tokens.
        strategy.deposit(address(token), AMOUNT);
        assertEq(token.balanceOf(address(strategy)), 0);
        assertEq(token.balanceOf(address(cloneFallback)), 0);
        assertEq(strategy.balanceOf(address(token)), AMOUNT);

        /// Earmark rewards to flow to BaseRewardPool.
        /// We prank to avoid receiving claimIncentive.
        vm.prank(address(0xBEEF));
        IBooster(BOOSTER).earmarkRewards(pid);

        /// Wait 7 days for rewards to accrue.
        skip(7 days);

        strategy.claim(address(token), true, true, true);

        // assertEq(cloneFallback.balanceOf(), AMOUNT);
        // assertEq(baseRewardPool.balanceOf(address(cloneFallback)), AMOUNT);
    }
}
