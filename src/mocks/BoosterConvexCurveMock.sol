// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

contract BoosterConvexCurveMock {
    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    PoolInfo[] public poolInfo;

    function addPool(address lpToken, address token, address gauge, address crvRewards) public {
        poolInfo.push(PoolInfo(lpToken, token, gauge, crvRewards, address(0), false));
    }
}
