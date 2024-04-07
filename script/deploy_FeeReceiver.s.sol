// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {FeeReceiver} from "src/strategy/FeeReceiver.sol";

/*

function run() public {
        vm.startBroadcast(deployer);

        ImmutableCreate2Factory factory = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

        address expectedAddress = 0x0000000895cB182E6f983eb4D8b4E0Aa0B31Ae4c;
        bytes32 salt = bytes32(0x00000000000000000000000000000000000000009507c6bc18ba0210002d039b);
        /// CURVE
        /// Address: 0x00000006a9C3E87Bd203ecde071665a6eAabe5EA
        /// Salt: 0x0000000000000000000000000000000000000000696e3563d59d23800099f57b
        _deployPlatform(factory, CURVE_CONTROLLER, salt, expectedAddress);

        vm.stopBroadcast();
    }

    function _deployPlatform(ImmutableCreate2Factory factory, address controller, bytes32 salt, address expectedAddress)
        internal
    {
        factory.safeCreate2(
            salt, abi.encodePacked(type(Platform).creationCode, abi.encode(controller, owner, deployer))
        );

        Platform platform = Platform(address(expectedAddress));

*/

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32, bytes memory) external;
}

contract PlatformScript is Script, Test {
    /// Executor
    address deployer = 0x90569D8A1cF801709577B24dA526118f0C83Fc75;
    
    /// Multisig
    address governance = address(0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063);

    function run() public {
        vm.startBroadcast(deployer);

        ImmutableCreate2Factory factory = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

        address expectedAddress = 0x0000002127E998fdd4149718664D5853b82E3557;

        bytes32 salt = bytes32(0x0000000000000000000000000000000000000000b46a76edbedbb50199e99276);
        
        factory.safeCreate2(
            salt, abi.encodePacked(type(FeeReceiver).creationCode, abi.encode(deployer, governance, governance))
        );

        FeeReceiver feeReceiver = FeeReceiver(address(expectedAddress));

        assertEq(feeReceiver.governance(), deployer);
        assertEq(feeReceiver.dao(), governance);
        assertEq(feeReceiver.veSdtFeeProxy(), governance);
        assertEq(feeReceiver.futureGovernance(), address(0));

        vm.stopBroadcast();
    }

}