// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "src/base/factory/PoolFactory.sol";

import {IBooster} from "src/base/interfaces/IBooster.sol";
import {IConvexFactory} from "src/base/interfaces/IConvexFactory.sol";
import {IGaugeController} from "src/base/interfaces/IGaugeController.sol";

/// @notice Inherit from PoolFactory to deploy a pool compatible with CRV gauges and check if the token is a valid extra rewards to add.
contract CRVPoolFactory is PoolFactory {
    /// @notice Ve Funder is a special gauge not valid to be deployed as a pool.
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    /// @notice Convex Booster.
    address public constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /// @notice Ve Funder is a special gauge not valid to be deployed as a pool.
    address public constant VE_FUNDER = 0xbAF05d7aa4129CA14eC45cC9d4103a9aB9A9fF60;

    /// @notice Convex Minimal Proxy Factory for Only Boost.
    address public constant CONVEX_MINIMAL_PROXY_FACTORY = 0x4E795A6f991e305e3f28A3b1b2B4B9789d2CD5A1;

    /// @notice Curve Gauge Controller.
    IGaugeController public constant GAUGE_CONTROLLER = IGaugeController(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);

    /// @notice Event emitted when a pool is deployed with Only Boost.
    event PoolDeployed(address vault, address rewardDistributor, address lp, address gauge, address stakingConvex);

    constructor(
        address _strategy,
        address _rewardToken,
        address _vaultImplementation,
        address _liquidityGaugeImplementation,
        address _rewardReceiverImplementation
    )
        PoolFactory(
            _strategy,
            _rewardToken,
            _vaultImplementation,
            _liquidityGaugeImplementation,
            _rewardReceiverImplementation
        )
    {}

    /// @notice Create a new pool for a given pid on the Convex platform.
    /// @param _pid Pool id.
    /// @return vault Address of the vault.
    /// @return rewardDistributor Address of the reward distributor.
    /// @return stakingConvex Address of the staking convex.
    function create(uint256 _pid) external returns (address vault, address rewardDistributor, address stakingConvex) {
        (address _token,, address _gauge,,,) = IBooster(BOOSTER).poolInfo(_pid);

        /// No necessary to check if the gauge is valid, as it's already checked in the ConvexMinimalProxyFactory.
        stakingConvex = IConvexFactory(CONVEX_MINIMAL_PROXY_FACTORY).create(_token, _pid);

        /// Create Stake DAO pool.
        (vault, rewardDistributor) = _create(_gauge);

        emit PoolDeployed(vault, rewardDistributor, _token, _gauge, stakingConvex);
    }

    /// @notice Add the main reward token to the reward distributor.
    /// @param rewardDistributor Address of the reward distributor.
    function _addRewardToken(address rewardDistributor) internal override {
        /// The strategy should claim through the locker the reward token,
        /// and distribute it to the reward distributor every harvest.
        ISDLiquidityGauge(rewardDistributor).add_reward(rewardToken, address(strategy));

        /// Add CVX in the case where Only Boost is enabled.
        ISDLiquidityGauge(rewardDistributor).add_reward(CVX, address(strategy));
    }

    /// @inheritdoc PoolFactory
    function _isValidToken(address _token) internal view override returns (bool) {
        /// We can't add the reward token as extra reward.
        /// We can't add special pools like the Ve Funder.
        /// We can't add SDT as extra reward, as it's already added by default.
        if (_token == rewardToken || _token == VE_FUNDER || _token == SDT) return false;

        /// If the token is available as an inflation receiver, it's not valid.
        try GAUGE_CONTROLLER.gauge_types(_token) {
            return false;
        } catch {
            return true;
        }
    }

    /// inheritdoc PoolFactory
    function _isValidGauge(address _gauge) internal view override returns (bool) {
        bool isValid;
        /// Check if the gauge is a valid candidate and available as an inflation receiver.
        /// This call always reverts if the gauge is not valid.
        try GAUGE_CONTROLLER.gauge_types(_gauge) {
            isValid = true;
        } catch {
            return false;
        }

        /// Check if the gauge is not killed.
        /// Not all the pools, but most of them, have this function.
        try ILiquidityGauge(_gauge).is_killed() returns (bool isKilled) {
            if (isKilled) return false;
        } catch {}

        /// If the gauge doesn't support the is_killed function, but is unofficially killed, it can be deployed.
        return isValid;
    }
}
