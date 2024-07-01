// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "src/curve/CRVStrategy.sol";
import "solady/utils/LibClone.sol";
import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "src/curve/fallbacks/ConvexImplementation.sol";
import "src/curve/fallbacks/ConvexMinimalProxyFactory.sol";

import {Vault} from "src/base/staking/Vault.sol";
import {IBooster} from "src/base/interfaces/IBooster.sol";
import {RewardReceiver} from "src/base/strategy/RewardReceiver.sol";
import {IGaugesOwnerProxy} from "src/base/interfaces/IGaugesOwnerProxy.sol";

import {ConvexMinimalProxyFactory} from "src/curve/fallbacks/ConvexMinimalProxyFactory.sol";
import {ISDLiquidityGauge, IGaugeController, PoolFactory, CRVPoolFactory} from "src/curve/factory/CRVPoolFactory.sol";

abstract contract PoolFactory_Test is Test {
    ILocker public locker;

    Vault vaultImplementation;
    RewardReceiver rewardReceiverImplementation;

    CRVPoolFactory poolFactory;

    CRVStrategy strategy;
    CRVStrategy implementation;

    ERC20 public token;
    address public gauge;

    address[] public extraRewardTokens;

    address public constant BOOSTER = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    IGaugeController public constant GAUGE_CONTROLLER = IGaugeController(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);

    address public constant VE_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address public constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;
    address public constant SD_VOTER_PROXY = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
    address public constant REWARD_TOKEN = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant FALLBACK_REWARD_TOKEN = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    address public constant GAUGES_OWNER_PROXY = 0x742C3cF9Af45f91B109a81EfEaf11535ECDe9571;

    address public constant RANDOM_GAUGE = 0x8F4ecCfaa4B6B0042970baDE0E3e9F3bE272B55f;
    address public constant RANDOM_TOKEN = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;

    address public constant gaugeImplementation = address(0xc1e4775B3A589784aAcD15265AC39D3B3c13Ca3c);

    uint256 pid;
    bool isShutdown;

    constructor(uint256 _pid, address _gauge) {
        bool _isShutdown;
        address lpToken;

        if (_gauge == address(0)) {
            /// Check if the LP token is valid
            (lpToken,,,,, _isShutdown) = IBooster(BOOSTER).poolInfo(_pid);
        } else {
            lpToken = ILiquidityGauge(_gauge).lp_token();
        }

        pid = _pid;
        isShutdown = _isShutdown;

        gauge = _gauge;
        token = ERC20(lpToken);
    }

    function setUp() public {
        vm.rollFork({blockNumber: 19_925_731});

        /// Deploy Strategy
        implementation = new CRVStrategy(address(this), SD_VOTER_PROXY, VE_CRV, REWARD_TOKEN, MINTER);

        // Clone strategy
        address _proxy = address(new ERC1967Proxy(address(implementation), ""));

        strategy = CRVStrategy(payable(_proxy));

        strategy.initialize(address(this));

        /// Initialize Locker
        locker = ILocker(SD_VOTER_PROXY);

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(payable(address(strategy)));

        vaultImplementation = new Vault();
        rewardReceiverImplementation = new RewardReceiver();

        ConvexImplementation _implementation = new ConvexImplementation();

        ConvexMinimalProxyFactory factory = new ConvexMinimalProxyFactory(
            BOOSTER, address(strategy), REWARD_TOKEN, FALLBACK_REWARD_TOKEN, address(_implementation)
        );

        poolFactory = new CRVPoolFactory(
            address(strategy),
            REWARD_TOKEN,
            address(vaultImplementation),
            address(factory),
            gaugeImplementation,
            address(rewardReceiverImplementation)
        );

        strategy.setFactory(address(poolFactory));
    }

    function test_deploy_pool_using_pid() public {
        if (pid == 0) return;

        address vault;
        address rewardDistributor;
        address stakingConvex;

        (,, address _gauge,,,) = IBooster(BOOSTER).poolInfo(pid);

        _addNativeExtraReward(_gauge);

        /// Create using the pid.
        (vault, rewardDistributor, stakingConvex) = poolFactory.create(pid, address(0));

        /// Vault Checks.
        assertEq(address(Vault(vault).token()), address(token));
        assertEq(address(Vault(vault).strategy()), address(strategy));
        assertEq(address(Vault(vault).liquidityGauge()), rewardDistributor);

        vm.expectRevert(Vault.ALREADY_INITIALIZED.selector);
        Vault(vault).initialize();

        /// Reward Distributor Checks.
        assertEq(ISDLiquidityGauge(rewardDistributor).vault(), vault);
        assertEq(ISDLiquidityGauge(rewardDistributor).staking_token(), vault);

        assertEq(ISDLiquidityGauge(rewardDistributor).reward_tokens(0), poolFactory.SDT());
        assertEq(ISDLiquidityGauge(rewardDistributor).reward_tokens(1), REWARD_TOKEN);
        assertEq(ISDLiquidityGauge(rewardDistributor).reward_tokens(2), FALLBACK_REWARD_TOKEN);

        /// Check for the distributors.
        ISDLiquidityGauge.Reward memory reward = ISDLiquidityGauge(rewardDistributor).reward_data(REWARD_TOKEN);
        assertEq(reward.distributor, address(strategy));

        reward = ISDLiquidityGauge(rewardDistributor).reward_data(FALLBACK_REWARD_TOKEN);
        address rewardReceiver = strategy.rewardReceivers(_gauge);

        assertEq(reward.distributor, address(rewardReceiver));

        /// Check if there's extra rewards in the gauge.
        _checkExtraRewards(_gauge, rewardDistributor, rewardReceiver);
    }

    function test_deploy_pool() public {
        if (gauge == address(0)) return;

        _addNativeExtraReward(gauge);

        address vault;
        address rewardDistributor;
        address stakingConvex;

        /// Create using the gauge.
        /// We can put any pid, it will be ignored.
        (vault, rewardDistributor, stakingConvex) = poolFactory.create(0, gauge);

        /// Vault Checks.
        assertEq(address(Vault(vault).token()), address(token));
        assertEq(address(Vault(vault).strategy()), address(strategy));
        assertEq(address(Vault(vault).liquidityGauge()), rewardDistributor);

        vm.expectRevert(Vault.ALREADY_INITIALIZED.selector);
        Vault(vault).initialize();

        /// Reward Distributor Checks.
        assertEq(ISDLiquidityGauge(rewardDistributor).vault(), vault);
        assertEq(ISDLiquidityGauge(rewardDistributor).staking_token(), vault);

        assertEq(ISDLiquidityGauge(rewardDistributor).reward_tokens(0), poolFactory.SDT());
        assertEq(ISDLiquidityGauge(rewardDistributor).reward_tokens(1), REWARD_TOKEN);
        assertEq(ISDLiquidityGauge(rewardDistributor).reward_tokens(2), FALLBACK_REWARD_TOKEN);

        /// Check for the distributors.
        ISDLiquidityGauge.Reward memory reward = ISDLiquidityGauge(rewardDistributor).reward_data(REWARD_TOKEN);
        assertEq(reward.distributor, address(strategy));

        reward = ISDLiquidityGauge(rewardDistributor).reward_data(FALLBACK_REWARD_TOKEN);
        address rewardReceiver = strategy.rewardReceivers(gauge);

        assertEq(reward.distributor, address(rewardReceiver));

        /// Check if there's extra rewards in the gauge.
        _checkExtraRewards(gauge, rewardDistributor, rewardReceiver);
    }

    function _checkExtraRewards(address _gauge, address rewardDistributor, address rewardReceiver) internal {
        // view function called only to recognize the gauge type
        bytes memory data = abi.encodeWithSignature("reward_tokens(uint256)", 0);
        (bool success,) = _gauge.call(data);
        if (!success) {
            assertEq(strategy.lGaugeType(_gauge), 1);
        } else {
            uint256 _count = 3; // 3 because we already checked for SDT and CRV
            for (uint8 i = 0; i < 8;) {
                // Get reward token
                address _extraRewardToken = ISDLiquidityGauge(_gauge).reward_tokens(i);

                if (_extraRewardToken == address(0)) {
                    break;
                }

                try GAUGE_CONTROLLER.gauge_types(_extraRewardToken) {
                    break;
                } catch {}

                ISDLiquidityGauge.Reward memory reward =
                    ISDLiquidityGauge(rewardDistributor).reward_data(_extraRewardToken);

                if (rewardReceiver != address(0) && _extraRewardToken != REWARD_TOKEN) {
                    assertEq(reward.distributor, rewardReceiver);
                } else {
                    assertEq(reward.distributor, address(strategy));
                }

                if (
                    _extraRewardToken != REWARD_TOKEN && _extraRewardToken != poolFactory.SDT()
                        && _extraRewardToken != FALLBACK_REWARD_TOKEN
                ) {
                    _count += 1;
                }

                unchecked {
                    ++i;
                }
            }
            assertEq(_count, ISDLiquidityGauge(rewardDistributor).reward_count());
        }
    }

    function _addNativeExtraReward(address _gauge) internal {
        address _owner = IGaugesOwnerProxy(GAUGES_OWNER_PROXY).gauge_manager(_gauge);
        if (_owner == address(0)) _owner = GAUGES_OWNER_PROXY;

        deal(address(REWARD_TOKEN), _owner, 1000e18);
        deal(address(FALLBACK_REWARD_TOKEN), _owner, 1000e18);
        deal(address(RANDOM_GAUGE), _owner, 1000e18);
        deal(address(RANDOM_TOKEN), _owner, 1000e18);

        vm.startPrank(_owner);
        /// Approve all.
        ERC20(REWARD_TOKEN).approve(_gauge, type(uint256).max);
        ERC20(FALLBACK_REWARD_TOKEN).approve(_gauge, type(uint256).max);
        ERC20(RANDOM_TOKEN).approve(_gauge, type(uint256).max);
        ERC20(RANDOM_GAUGE).approve(_gauge, type(uint256).max);

        ILiquidityGauge(_gauge).add_reward(REWARD_TOKEN, _owner);
        ILiquidityGauge(_gauge).add_reward(FALLBACK_REWARD_TOKEN, _owner);
        ILiquidityGauge(_gauge).add_reward(RANDOM_TOKEN, _owner);
        ILiquidityGauge(_gauge).add_reward(RANDOM_GAUGE, _owner);

        ILiquidityGauge(_gauge).deposit_reward_token(REWARD_TOKEN, 1000e18);
        ILiquidityGauge(_gauge).deposit_reward_token(FALLBACK_REWARD_TOKEN, 1000e18);
        ILiquidityGauge(_gauge).deposit_reward_token(RANDOM_TOKEN, 1000e18);
        ILiquidityGauge(_gauge).deposit_reward_token(RANDOM_GAUGE, 1000e18);

        vm.stopPrank();
    }
}
