// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "src/strategy/Strategy.sol";

/// @title OnlyBoost Strategy Contract
/// @author Stake DAO
/// @notice OnlyBoost Compatible Strategy Proxy Contract to interact with Stake DAO Locker.
contract CRV_Strategy is Strategy {
    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        Strategy(_owner, _locker, _veToken, _rewardToken, _minter)
    {}
}
