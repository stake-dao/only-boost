// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "forge-std/Test.sol";

contract CRVMinter is Test {
    address public CRV;

    constructor(address _CRV) {
        CRV = _CRV;
    }

    function mint(address) external {
        // Do nothing
        deal(CRV, msg.sender, 1000e18);
    }
}
