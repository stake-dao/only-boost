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

    function _isValidToken(address _token) internal view override returns (bool) {
        if (_token == rewardToken || _token == VE_FUNDER) return false;

        try GAUGE_CONTROLLER.gauge_types(_token) {
            return false;
        } catch {
            return true;
        }
    }

    function _isValidGauge(address _gauge) internal view override returns (bool) {
        uint256 weight = IGaugeController(GAUGE_CONTROLLER).get_gauge_weight(_gauge);
        if (weight == 0) return false;

        /// Check if the gauge is not killed.
        /// Not all the pools, but most of them, have this function.
        try ILiquidityGauge(_gauge).is_killed() returns (bool isKilled) {
            if (isKilled) return false;
        } catch {}

        return true;
    }
}
