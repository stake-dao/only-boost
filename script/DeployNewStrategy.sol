// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/src/Script.sol";

contract DeployNewStrategy is Script {
    function run() public {
        vm.startBroadcast();

        vm.stopBroadcast();
    }
}