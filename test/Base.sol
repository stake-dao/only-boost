// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import "src/v2/CRVStrategy.sol";
import {ILocker} from "src/interfaces/ILocker.sol";
import {Optimizer} from "src/v2/only-boost-helper/Optimizer.sol";

import {SafeTransferLib as SafeTransfer} from "solady/src/utils/SafeTransferLib.sol";
import {ConvexImplementation} from "src/v2/fallbacks/convex/ConvexImplementation.sol";
import {IBooster, ConvexMinimalProxyFactory} from "src/v2/fallbacks/convex/ConvexMinimalProxyFactory.sol";

abstract contract Base_Test is Test {
    using SafeTransfer for ERC20;

    ILocker public locker;
    Optimizer public optimizer;
    CRVStrategy public strategy;

    ConvexMinimalProxyFactory public factory;

    /// @notice Implementation contract to clone.
    ConvexImplementation public implementation;

    /// @notice Convex Depositor.
    ConvexImplementation public proxy;

    //////////////////////////////////////////////////////
    /// --- CONVEX ADDRESSES
    //////////////////////////////////////////////////////

    address public constant BOOSTER = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant REWARD_TOKEN = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant FALLBACK_REWARD_TOKEN = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    //////////////////////////////////////////////////////
    /// --- VOTER PROXY ADDRESSES
    //////////////////////////////////////////////////////

    address public constant SD_VOTER_PROXY = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
    address public constant CONVEX_VOTER_PROXY = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    //////////////////////////////////////////////////////
    /// --- CURVE ADDRESSES
    //////////////////////////////////////////////////////

    address public constant VE_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address public constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;

    uint256 public pid;
    ERC20 public token;
    address public gauge;
    address public rewardDistributor;

    constructor(uint256 _pid, address _rewardDistributor) {
        /// Check if the LP token is valid
        (address lpToken,, address _gauge,,,) = IBooster(BOOSTER).poolInfo(_pid);

        pid = _pid;
        gauge = _gauge;
        token = ERC20(lpToken);
        rewardDistributor = _rewardDistributor;
    }

    function setUp() public virtual {
        /// Initialize Locker
        locker = ILocker(SD_VOTER_PROXY);

        strategy = new CRVStrategy(
            address(this),
            SD_VOTER_PROXY,
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

        proxy = ConvexImplementation(factory.create(address(token), pid));

        token.approve(address(strategy), type(uint256).max);

        /// Initialize token config.
        strategy.setGauge(address(token), address(gauge));
        strategy.setRewardDistributor(address(gauge), address(rewardDistributor));

        vm.prank(ILiquidityGauge(address(rewardDistributor)).admin());
        /// Transfer Ownership of the gauge to the strategy.
        ILiquidityGauge(address(rewardDistributor)).commit_transfer_ownership(address(strategy));

        /// Accept ownership of the gauge.
        strategy.execute(address(rewardDistributor), 0, abi.encodeWithSignature("accept_transfer_ownership()"));

        /// Add the extra reward token.
        _addExtraRewardToken();

        /// We need to overwrite the locker balance.
        deal(address(gauge), address(locker), 0);
    }

    function _addExtraRewardToken() internal {
        /// Add the reward token to the rewardDistributor.
        strategy.addRewardToken(gauge, FALLBACK_REWARD_TOKEN);

        /// Update the rewardToken distributor to the strategy.
        strategy.execute(
            address(rewardDistributor),
            0,
            abi.encodeWithSignature("set_reward_distributor(address,address)", REWARD_TOKEN, address(strategy))
        );

        uint256 _extraRewardTokenLength = proxy.baseRewardPool().extraRewardsLength();

        if (_extraRewardTokenLength > 0) {
            for (uint256 i; i < _extraRewardTokenLength; i++) {
                address _extraRewardToken = proxy.baseRewardPool().extraRewards(i);

                // If not already added in the rewardDistributor.
                address distributor = ILiquidityGauge(rewardDistributor).reward_data(_extraRewardToken).distributor;
                if (distributor != address(0)) {
                    strategy.addRewardToken(gauge, _extraRewardToken);
                } else {
                    /// Update the rewardToken distributor to the strategy.
                    strategy.execute(
                        address(rewardDistributor),
                        0,
                        abi.encodeWithSignature(
                            "set_reward_distributor(address,address)", _extraRewardToken, address(strategy)
                        )
                    );
                }
            }
        } else {
            strategy.setLGtype(gauge, 1);
        }
    }
}
