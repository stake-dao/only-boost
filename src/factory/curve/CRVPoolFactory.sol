// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "src/factory/PoolFactory.sol";
import {IGaugeController} from "src/interfaces/IGaugeController.sol";

/// @notice Inherit from PoolFactory to deploy a pool compatible with CRV gauges and check if the token is a valid extra rewards to add.
contract CRVPoolFactory is PoolFactory {
    /// @notice Ve Funder is a special gauge not valid to be deployed as a pool.
    address public constant VE_FUNDER = 0xbAF05d7aa4129CA14eC45cC9d4103a9aB9A9fF60;

    /// @notice Curve Gauge Controller.
    IGaugeController public constant GAUGE_CONTROLLER = IGaugeController(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);

    constructor(
        address _strategy,
        address _rewardToken,
        address _vaultImplementation,
        address _liquidityGaugeImplementation
    ) PoolFactory(_strategy, _rewardToken, _vaultImplementation, _liquidityGaugeImplementation) {}

    /// @inheritdoc PoolFactory
    function _isValidToken(address _token) internal view override returns (bool) {
        /// We can't add the reward token as extra reward.
        /// We can't add special pools like the Ve Funder.
        if (_token == rewardToken || _token == VE_FUNDER) return false;

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
