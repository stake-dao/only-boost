// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import "src/CRVStrategy.sol";
import "solady/utils/LibClone.sol";
import {Vault} from "src/staking/Vault.sol";
import {IBooster} from "src/interfaces/IBooster.sol";
import {ISDLiquidityGauge, IGaugeController, PoolFactory, CRVPoolFactory} from "src/factory/curve/CRVPoolFactory.sol";

abstract contract PoolFactory_Test is Test {
    ILocker public locker;

    Vault vaultImplementation;
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

    address public constant gaugeImplementation = address(0x3Dc56D46F0Bd13655EfB29594a2e44534c453BF9);

    constructor(uint256 _pid) {
        /// Check if the LP token is valid
        (address lpToken,, address _gauge,,,) = IBooster(BOOSTER).poolInfo(_pid);

        gauge = _gauge;
        token = ERC20(lpToken);
    }

    function setUp() public {
        vm.rollFork({blockNumber: 18_383_019});

        /// Deploy Strategy
        implementation = new CRVStrategy(address(this), SD_VOTER_PROXY, VE_CRV, REWARD_TOKEN, MINTER);

        address _proxy = LibClone.deployERC1967(address(implementation));
        strategy = CRVStrategy(payable(_proxy));

        strategy.initialize(address(this));

        /// Initialize Locker
        locker = ILocker(SD_VOTER_PROXY);

        // Give strategy roles from depositor to new strategy
        vm.prank(locker.governance());
        locker.setStrategy(payable(address(strategy)));

        vaultImplementation = new Vault();

        poolFactory =
            new CRVPoolFactory(address(strategy), REWARD_TOKEN, address(vaultImplementation), gaugeImplementation);

        strategy.setFactory(address(poolFactory));
    }

    function test_deploy_pool() public {
        address vault;
        address rewardDistributor;

        /// Check if the gauge is not killed.
        /// Not all the pools, but most of them, have this function.
        bool isKilled;
        try ILiquidityGauge(gauge).is_killed() returns (bool _isKilled) {
            isKilled = _isKilled;
        } catch {}

        if (isKilled) {
            vm.expectRevert(PoolFactory.INVALID_GAUGE.selector);
            (vault, rewardDistributor) = poolFactory.create(gauge);
        } else {
            (vault, rewardDistributor) = poolFactory.create(gauge);

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

            /// Check if there's extra rewards in the gauge.
            _checkExtraRewards(rewardDistributor);
        }
    }

    function _checkExtraRewards(address rewardDistributor) public {
        // view function called only to recognize the gauge type
        bytes memory data = abi.encodeWithSignature("reward_tokens(uint256)", 0);
        (bool success,) = gauge.call(data);
        if (!success) {
            assertEq(strategy.lGaugeType(gauge), 1);
        } else {
            uint256 _count = 3; // 3 because we already checked for SDT and CRV
            for (uint8 i = 0; i < 8;) {
                // Get reward token
                address _extraRewardToken = ISDLiquidityGauge(gauge).reward_tokens(i);
                if (_extraRewardToken == address(0)) {
                    break;
                }

                ISDLiquidityGauge.Reward memory reward =
                    ISDLiquidityGauge(rewardDistributor).reward_data(_extraRewardToken);
                assertEq(reward.distributor, address(strategy));

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
}
