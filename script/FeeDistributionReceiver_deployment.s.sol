// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {FeeReceiver} from "src/base/strategy/FeeReceiver.sol";

contract PlatformScript is Script, Test {
    /// Executor
    address deployer = 0x90569D8A1cF801709577B24dA526118f0C83Fc75;

    /// Multisig
    address governance = address(0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063);

    function run() public {
        vm.startBroadcast(deployer);

        FeeReceiver feeReceiver = new FeeReceiver(deployer);

        assertEq(feeReceiver.governance(), deployer);
        assertEq(feeReceiver.futureGovernance(), address(0));

        vm.stopBroadcast();
    }
}
