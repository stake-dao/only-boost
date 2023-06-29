// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {Authority} from "solmate/auth/Auth.sol";
import {RolesAuthority} from "solmate/auth/authorities/RolesAuthority.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {LibString} from "solady/src/utils/LibString.sol";

import {Optimizor} from "src/Optimizor.sol";
import {BaseFallback} from "src/BaseFallback.sol";
import {CurveStrategy} from "src/CurveStrategy.sol";
import {FallbackConvexFrax} from "src/FallbackConvexFrax.sol";
import {FallbackConvexCurve} from "src/FallbackConvexCurve.sol";

import {OptimizorMock} from "src/mocks/OptimizorMock.sol";
import {LiquidLockerMock} from "src/mocks/LiquidLockerMock.sol";
import {PoolRegistryMock} from "src/mocks/PoolRegistryMock.sol";
import {BaseRewardPoolMock} from "src/mocks/BaseRewardPoolMock.sol";
import {LiquidityGaugeMock} from "src/mocks/LiquidityGaugeMock.sol";
import {BoosterConvexFraxMock} from "src/mocks/BoosterConvexFraxMock.sol";
import {BoosterConvexCurveMock} from "src/mocks/BoosterConvexCurveMock.sol";

import {Handler} from "test/invariants/Handler.t.sol";

contract CurveStrategyInvariantsTest is Test {
    using stdStorage for StdStorage;

    address public immutable STK_ALUSD_FRAXBP = makeAddr("STK_ALUSD_FRAXBP");

    MockERC20 public CRV;
    MockERC20 public CRV3;
    MockERC20 public ALUSD_FRAXBP;
    MockERC20 public STETH_ETH;

    PoolRegistryMock public poolRegistryMock;
    LiquidLockerMock public liquidLockerMock;
    LiquidityGaugeMock public liquidityGaugeCRV3Mock;
    BoosterConvexFraxMock public boosterConvexFraxMock;
    BoosterConvexCurveMock public boosterConvexCurveMock;

    OptimizorMock public optimizor;
    CurveStrategy public curveStrategy;
    RolesAuthority public rolesAuthority;
    FallbackConvexFrax public fallbackConvexFrax;
    FallbackConvexCurve public fallbackConvexCurve;

    function setUp() public {}
}
