// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {BaseFallback, IPoolRegistryConvexFrax} from "./BaseFallback.sol";

contract FallbackConvexFrax is BaseFallback {
    mapping(address => address) public stkTokens; // lpToken address --> staking token contract address

    constructor() {
        poolRegistryConvexFrax = IPoolRegistryConvexFrax(0x41a5881c17185383e19Df6FA4EC158a6F4851A69);

        setAllPidsOptimized();
    }

    function setPid(uint256 index) public override {
        // Get the staking token address
        (,, address stkToken,,) = poolRegistryConvexFrax.poolInfo(index);

        // Get the underlying curve lp token address
        (bool success, bytes memory data) = stkToken.call(abi.encodeWithSignature("curveToken()"));

        if (success) {
            // Map the stkToken address from ConvexFrax to the curve lp token
            stkTokens[abi.decode(data, (address))] = stkToken;
            // Map the pool infos to stkToken address from ConvexFrax
            pids[stkToken] = PidsInfo(index, true);
        }
    }

    function setAllPidsOptimized() public override {
        // Cache the length of the pool registry
        uint256 len = poolRegistryConvexFrax.poolLength();

        // If the length is the same, no need to update
        if (lastPidsCount == len) return;

        // If the length is smaller, update pids mapping
        for (uint256 i = lastPidsCount; i < len; ++i) {
            setPid(i);
        }

        // Update the last length
        lastPidsCount = len;
    }

    function isActive(address lpToken) public override returns (bool) {
        setAllPidsOptimized();

        (,,,, uint8 _isActive) = poolRegistryConvexFrax.poolInfo(pids[stkTokens[lpToken]].pid);
        return pids[lpToken].isInitialized && _isActive == 1;
    }
}
