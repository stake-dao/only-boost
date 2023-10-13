// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {Clone} from "solady/src/utils/Clone.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract ConvexImplementation is Clone {
    using SafeTransferLib for ERC20;

    function token() public pure returns (address _token) {
        return _getArgAddress(0);
    }

    function rewardToken() public pure returns (address _rewardToken) {
        return _getArgAddress(20);
    }

    function fallbackRewardToken() public pure returns (address _fallbackRewardToken) {
        return _getArgAddress(40);
    }

    function strategy() public pure returns (address _strategy) {
        return _getArgAddress(60);
    }

    function booster() public pure returns (address _booster) {
        return _getArgAddress(80);
    }

    function baseRewardPool() public pure returns (address _baseRewardPool) {
        return _getArgAddress(100);
    }

    function pid() public pure returns (uint256 _pid) {
        return _getArgUint256(120);
    }

    function initialize() external {
        ERC20(token()).safeApprove(booster(), type(uint256).max);
    }

    modifier onlyStrategy() {
        require(msg.sender == strategy(), "ConvexImplementation: Only strategy");
        _;
    }
}
