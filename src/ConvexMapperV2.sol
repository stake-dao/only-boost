// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {IBoosterConvexCurve} from "src/interfaces/IBoosterConvexCurve.sol";
import {IPoolRegistryConvexFrax} from "src/interfaces/IPoolRegistryConvexFrax.sol";
import {IConvexStakingWrapperFrax} from "src/interfaces/IConvexStakingWrapperFrax.sol";

contract ConvexMapper {
    struct PidsInfo {
        uint256 pid;
        uint256 curveOrFrax; // 1 = curve, 2 = frax
    }

    IBoosterConvexCurve public boosterConvexCurve; // Convex booster
    IPoolRegistryConvexFrax public poolRegistryConvexFrax; // ConvexFrax pool Registry

    uint256 public lastPidsCountConvexFrax; // Number of pools on ConvexFrax
    uint256 public lastPidsCountConvexCurve; // Number of pools on ConvexCurve

    mapping(address => PidsInfo) public pidsCurve; // lpToken address --> pool ids from convexCurve
    mapping(address => PidsInfo) public pidsFrax; // lpToken address --> pool ids from convexFrax
    mapping(address => address) public stkTokens; // lpToken address --> staking token contract address

    constructor() {
        boosterConvexCurve = IBoosterConvexCurve(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
        poolRegistryConvexFrax = IPoolRegistryConvexFrax(0x41a5881c17185383e19Df6FA4EC158a6F4851A69);
        setAllPidsOnConvexFraxOptimized();
        setAllPidsOnConvexCurveOptimized();
    }

    function getPidsCurve(address lpToken) public view returns (PidsInfo memory) {
        return pidsCurve[lpToken];
    }

    function getPidsFrax(address lpToken) public view returns (PidsInfo memory) {
        return pidsFrax[stkTokens[lpToken]];
    }

    // === Convex Curve === //
    function setPidOnConvexCurve(uint256 index) public {
        // Get the lpToken address
        (address lpToken,,,,,) = boosterConvexCurve.poolInfo(index);

        // Map the lpToken to the pool infos
        pidsCurve[lpToken] = PidsInfo(index, 1);
    }

    function setAllPidsOnConvexCurveOptimized() public {
        // Cache the length of the pool registry
        uint256 len = boosterConvexCurve.poolLength();

        // If the length is the same, no need to update
        if (lastPidsCountConvexCurve == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = lastPidsCountConvexCurve; i < len; ++i) {
            setPidOnConvexCurve(i);
        }

        // Update the last length
        lastPidsCountConvexCurve = len;
    }

    // === Convex Frax === //
    function setPidOnConvexFrax(uint256 index) public {
        // Get the staking token address
        (,, address stkToken,,) = poolRegistryConvexFrax.poolInfo(index);

        // Get the underlying curve lp token address
        (bool success, bytes memory data) = stkToken.call(abi.encodeWithSignature("curveToken()"));

        if (success) {
            // Map the stkToken address from ConvexFrax to the curve lp token
            stkTokens[abi.decode(data, (address))] = stkToken;
            // Map the pool infos to stkToken address from ConvexFrax
            pidsFrax[stkToken] = PidsInfo(index, 2);
        }
    }

    function setAllPidsOnConvexFraxOptimized() public {
        // Cache the length of the pool registry
        uint256 len = poolRegistryConvexFrax.poolLength();

        // If the length is the same, no need to update
        if (lastPidsCountConvexFrax == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = lastPidsCountConvexFrax; i < len; ++i) {
            setPidOnConvexFrax(i);
        }

        // Update the last length
        lastPidsCountConvexFrax = len;
    }

    function getPid(address token)
        public
        returns (uint256 pidCurve, uint256 pidFrax, bool statusCurve, bool statusFrax)
    {
        // Check that no pids is missing
        setAllPidsOnConvexFraxOptimized();
        setAllPidsOnConvexCurveOptimized();

        // Returns the pids
        pidCurve = pidsCurve[token].pid;
        pidFrax = pidsFrax[stkTokens[token]].pid;

        // Get status
        (,,,,, bool shutdown) = boosterConvexCurve.poolInfo(pidCurve);
        (,,,, uint8 isActive) = poolRegistryConvexFrax.poolInfo(pidFrax);

        // Returns status
        statusCurve = !shutdown;
        statusFrax = isActive == 1;
    }

    function isActiveOnCurveOrFrax(address token) public returns (bool statusCurve, bool statusFrax) {
        // Check that no pids is missing
        setAllPidsOnConvexFraxOptimized();
        setAllPidsOnConvexCurveOptimized();

        (,,,,, bool shutdown) = boosterConvexCurve.poolInfo(pidsCurve[token].pid);
        (,,,, uint8 isActive) = poolRegistryConvexFrax.poolInfo(pidsFrax[stkTokens[token]].pid);

        // Returns status
        statusCurve = !shutdown;
        statusFrax = isActive == 1;
    }
}
