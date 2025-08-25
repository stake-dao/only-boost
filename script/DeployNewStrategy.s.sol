// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/src/Script.sol";
import {CRVStrategy} from "src/CRVStrategy.sol";
import {CurveShutdownStrategy} from "src/shutdown/v2/CurveShutdownStrategy.sol";

contract DeployNewStrategy is Script {
    /// @notice The CRVStrategy that'll be upgraded.
    CRVStrategy public crvStrategy = CRVStrategy(payable(0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd));

    function run() public {
        address deployer = vm.envAddress("DEPLOYER");
        vm.startBroadcast(deployer);

        new CurveShutdownStrategy({
            _owner: crvStrategy.governance(),
            _locker: address(crvStrategy.locker()),
            _veToken: crvStrategy.veToken(),
            _rewardToken: crvStrategy.rewardToken(),
            _minter: crvStrategy.minter()
        });

        vm.stopBroadcast();
    }
}
