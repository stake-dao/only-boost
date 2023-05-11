// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";
import {IPoolRegistryConvexFrax} from "src/interfaces/IPoolRegistryConvexFrax.sol";

contract ConvexMapper {
    IBoosterConvexCurve public boosterConvexCurve; // Convex booster
    IPoolRegistryConvexFrax public poolRegistryConvexFrax; // ConvexFrax pool Registry

    uint256 public pidsCountConvexFrax; // Number of pools on ConvexFrax
    uint256 public pidsCountConvexCurve; // Number of pools on ConvexCurve

    mapping(address => uint256) public pidsConvexFrax; // lpToken address --> pool ids from convexFrax
    mapping(address => uint256) public pidsConvexCurve; // lpToken address --> pool ids from convexCurve

    constructor() {
        boosterConvexCurve = IBoosterConvexCurve(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
        poolRegistryConvexFrax = IPoolRegistryConvexFrax(0x41a5881c17185383e19Df6FA4EC158a6F4851A69);
    }

    // === Convex Curve === //
    function setPidOnConvexCurve(uint256 index) public {
        (address lpToken,,,,,) = boosterConvexCurve.poolInfo(index);

        // If the lpToken is not in the list, add it
        if (pidsConvexFrax[lpToken] == 0) ++pidsCountConvexCurve;

        // Set the lpToken address
        pidsConvexCurve[lpToken] = index;
    }

    function setAllPidsOnConvexCurveOptimized() public {
        // Cache the length of the pool registry
        uint256 len = boosterConvexCurve.poolLength();

        // If the length is the same, no need to update
        if (pidsCountConvexCurve == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = pidsCountConvexCurve; i < len; ++i) {
            setPidOnConvexCurve(i);
        }
    }

    // === Convex Frax === //
    function setPidOnConvexFrax(uint256 index) public {
        (,, address lpToken,,) = poolRegistryConvexFrax.poolInfo(index);

        // If the lpToken is not in the list, add it
        if (pidsConvexFrax[lpToken] == 0) ++pidsCountConvexFrax;

        // Set the lpToken address
        pidsConvexFrax[lpToken] = index;
    }

    function setAllPidsOnConvexFraxOptimized() public {
        // Cache the length of the pool registry
        uint256 len = poolRegistryConvexFrax.poolLength();

        // If the length is the same, no need to update
        if (pidsCountConvexFrax == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = pidsCountConvexFrax; i < len; ++i) {
            setPidOnConvexFrax(i);
        }
    }

    function isOnConvexFrax(address token) public returns (bool) {
        // Check that no pids is missing
        setAllPidsOnConvexFraxOptimized();
        // Check if the pool is active
        (,,,, uint8 isActive) = poolRegistryConvexFrax.poolInfo(pidsConvexFrax[token]);

        return isActive == 1;
    }
}
