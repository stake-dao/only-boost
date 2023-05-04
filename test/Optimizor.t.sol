// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "lib/forge-std/src/Test.sol";

import {Optimizor} from "src/Optimizor.sol";

contract OptimizorTest is Test {
    Optimizor public optimizor;

    function setUp() public {
        // 17136445 : 27 April 2023 08:51:23 UTC
        // 17136745 : 27 April 2023 09:51:47 UTC
        // 17137000 : 27 April 2023 10:43:59 UTC
        // Create Fork
        vm.selectFork(vm.createFork(vm.rpcUrl("mainnet"), 17137000));

        // Deploy Optimizor
        optimizor = new Optimizor();
    }

    function test_Optimization1() public view {
        optimizor.optimization1();
    }

    function test_Optimization2() public view {
        optimizor.optimization2();
    }

    function test_Optimization3() public view {
        optimizor.optimization3();
    }
}
