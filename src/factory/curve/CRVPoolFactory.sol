// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "src/factory/PoolFactory.sol";
import {IGaugeController} from "src/interfaces/IGaugeController.sol";

/// @notice Inherit from PoolFactory to deploy a pool compatible with CRV gauges and check if the token is a valid extra rewards to add.
contract CRVPoolFactory is PoolFactory {
    address public constant VE_FUNDER = 0xbAF05d7aa4129CA14eC45cC9d4103a9aB9A9fF60;
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
            /// Do nothing
        }

        return true;
    }
}
