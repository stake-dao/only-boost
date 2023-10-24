// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

/// @title Locker Manager
/// @author Stake DAO
/// @notice Implements locker manager logic for YFI locker.
contract LockerManager {
    /// @notice Increase token amount locked
    /// @param value Amount of token to lock
    function increaseAmount(uint256 value) external {}

    /// @notice Extend unlock time on the locker
    /// @param unlock_time New epoch time for unlocking
    function increaseUnlockTime(uint256 unlock_time) external {}

    /// @notice Release all token locked
    function release() external virtual {}

    /// @notice Set the governance address
    /// @param _governance Address of the new governance
    function transferLockerGovernance(address _governance) external {}

    /// @notice Set the strategy address
    /// @dev Calling this function will disable the current strategy.
    /// @param _strategy Address of the new strategy
    function transferLockerStrategy(address _strategy) external {}
}
