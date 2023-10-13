// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {LibClone} from "solady/src/utils/LibClone.sol";

/// @title ConvexFallback
/// @author Stake DAO
/// @notice Manage LP deposit/withdraw/claim into Convex like platforms.
contract ConvexMinimalProxyFactory {
    using LibClone for address;

    address public immutable implementation;

    constructor(address _implementation) {
        implementation = _implementation;
    }

    /// @notice Create a new ConvexFallback contract
    /// @param _token LP token address
    /// @param _fallbackRewardToken Fallback reward token address
    /// @param _strategy Strategy address
    /// @param _booster Booster address
    /// @param _baseRewardPool Base reward pool address
    /// @param _pid Pool id from Convex
    /// @return _fallback New ConvexFallback contract address
    function create(
        address _token,
        address _rewardToken,
        address _fallbackRewardToken,
        address _strategy,
        address _booster,
        address _baseRewardPool,
        uint256 _pid
    ) external returns (address _fallback) {
        bytes memory data =
            abi.encodePacked(_token, _rewardToken, _fallbackRewardToken, _strategy, _booster, _baseRewardPool, _pid);

        bytes32 salt = keccak256(abi.encodePacked(_token, _pid));
        // Clone the implementation
        _fallback = implementation.cloneDeterministic(data, salt);

    }
}
