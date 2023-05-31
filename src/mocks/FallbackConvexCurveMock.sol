// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "../BaseFallback.sol";

contract FallbackConvexCurveMock is BaseFallback {
    constructor(address _curveStrategy) BaseFallback(address(0), Authority(address(0)), _curveStrategy) {}

    function isActive(address) external pure override returns (bool) {
        return false;
    }
}
