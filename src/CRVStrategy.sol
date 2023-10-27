// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "src/strategy/only-boost/OnlyBoost.sol";

/// @notice Strategy contract, supporting only the boost function.
contract CRVStrategy is OnlyBoost {
    constructor(address _owner, address _locker, address _veToken, address _rewardToken, address _minter)
        OnlyBoost(_owner, _locker, _veToken, _rewardToken, _minter)
    {}
}
