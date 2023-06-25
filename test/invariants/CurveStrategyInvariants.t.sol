// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {Authority} from "solmate/auth/Auth.sol";
import {RolesAuthority} from "solmate/auth/authorities/RolesAuthority.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {Optimizor} from "src/Optimizor.sol";
import {BaseFallback} from "src/BaseFallback.sol";
import {CurveStrategy} from "src/CurveStrategy.sol";
import {FallbackConvexFrax} from "src/FallbackConvexFrax.sol";
import {FallbackConvexCurve} from "src/FallbackConvexCurve.sol";

import {PoolRegistryMock} from "src/mocks/PoolRegistryMock.sol";
import {BoosterConvexFraxMock} from "src/mocks/BoosterConvexFraxMock.sol";
import {BoosterConvexCurveMock} from "src/mocks/BoosterConvexCurveMock.sol";

contract CurveStrategyInvariantsTest is Test {
    using stdStorage for StdStorage;

    MockERC20 public immutable CRV = new MockERC20("Curve DAO Token", "CRV", 18);
    MockERC20 public immutable CRV3 = new MockERC20("3 Pool", "CRV3", 18);
    MockERC20 public immutable ALUSD_FRAXBP = new MockERC20("Alchemix USD FraxBasePool", "ALUSD_FRAXBP", 18);
    MockERC20 public immutable STETH_ETH = new MockERC20("STETH ETH Pool", "STETH_ETH", 18);

    PoolRegistryMock public poolRegistryMock = new PoolRegistryMock();
    BoosterConvexFraxMock public boosterConvexFraxMock = new BoosterConvexFraxMock();
    BoosterConvexCurveMock public boosterConvexCurveMock = new BoosterConvexCurveMock();

    Optimizor public optimizor;
    CurveStrategy public curveStrategy;
    RolesAuthority public rolesAuthority;
    FallbackConvexFrax public fallbackConvexFrax;
    FallbackConvexCurve public fallbackConvexCurve;

    function setUp() public {}
}
