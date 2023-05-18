// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import "forge-std/Test.sol";

// Libraries
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// Contracts
import {Optimizor} from "src/Optimizor.sol";
import {CurveStrategy} from "src/CurveStrategy.sol";

// Interfaces
import {ILocker} from "src/interfaces/ILocker.sol";
import {IFraxUnifiedFarm} from "src/interfaces/IFraxUnifiedFarm.sol";
import {IBoosterConvexFrax} from "src/interfaces/IBoosterConvexFrax.sol";
import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";
import {IPoolRegistryConvexFrax} from "src/interfaces/IPoolRegistryConvexFrax.sol";

contract BaseTest is Test {
    ERC20 public constant CRV3 = ERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    ERC20 public constant ALUSD_FRAXBP = ERC20(0xB30dA2376F63De30b42dC055C93fa474F31330A5);

    address public constant GAUGE_CRV3 = 0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A;
    address public constant GAUGE_ALUSD_FRAXBP = 0x740BA8aa0052E07b925908B380248cb03f3DE5cB;
    address public constant LOCKER_STAKEDAO = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6; // StakeDAO CRV Locker
    address public constant LOCKER_CONVEX = 0x989AEb4d175e16225E39E87d0D97A3360524AD80; // Convex CRV Locker

    uint256 public constant MAX = type(uint256).max;
    uint256 public constant REF_AMOUNT = 1_000e18;

    mapping(address => address) public gauges;

    constructor() {
        labelAddress();
        gauges[address(CRV3)] = GAUGE_CRV3;
        gauges[address(ALUSD_FRAXBP)] = GAUGE_ALUSD_FRAXBP;
    }

    function labelAddress() internal {
        vm.label(address(CRV3), "CRV3");
        vm.label(address(ALUSD_FRAXBP), "ALUSD_FRAXBP");
        vm.label(GAUGE_CRV3, "GAUGE_CRV3");
        vm.label(GAUGE_ALUSD_FRAXBP, "GAUGE_ALUSD_FRAXBP");
    }
}
