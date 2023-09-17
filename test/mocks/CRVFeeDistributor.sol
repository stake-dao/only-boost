// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

contract CRVFeeDistributor is Test {
    address public CRV3;

    constructor(address _CRV3) {
        CRV3 = _CRV3;
    }

    function mint(address) external {
        // Do nothing
        deal(CRV3, msg.sender, 1000e18);
    }
}
