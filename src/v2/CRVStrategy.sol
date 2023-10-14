// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

/// TODO: For testing, remove for production
//import "forge-std/Test.sol";

import "src/v2/OnlyBoost.sol";

/// @title OnlyBoost Strategy Contract
/// @author Stake DAO
/// @notice OnlyBoost Compatible Strategy Proxy Contract to interact with Stake DAO Locker.
contract CRVStrategy is OnlyBoost {
    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        OnlyBoost(_owner, _locker, _veToken, _rewardToken, _minter)
    {}
}
