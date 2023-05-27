// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract BaseFallback {
    struct PidsInfo {
        uint256 pid;
        bool isInitialized;
    }

    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    uint256 public lastPidsCount; // Number of pools on ConvexCurve or ConvexFrax
    uint256 public feesOnRewards; // Fees to be collected from the strategy, in WAD unit

    address public feesReceiver = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063; // Address to receive fees, MS Stake DAO
    mapping(address => PidsInfo) public pids; // lpToken address --> pool ids from ConvexCurve or ConvexFrax

    event Deposited(address token, uint256 amount);
    event Withdrawn(address token, uint256 amount);
    event ClaimedRewards(address token, uint256 amountCRV, uint256 amountCVX);

    function setFeesOnRewards(uint256 _feesOnRewards) external {
        feesOnRewards = _feesOnRewards;
    }

    function setFeesReceiver(address _feesReceiver) external {
        feesReceiver = _feesReceiver;
    }

    function setPid(uint256 index) public virtual {}

    function setAllPidsOptimized() public virtual {}

    function isActive(address lpToken) external virtual returns (bool) {}

    function balanceOf(address lpToken) external view virtual returns (uint256) {}

    function deposit(address lpToken, uint256 amount) external virtual {}

    function withdraw(address lpToken, uint256 amount) external virtual {}

    function claimRewards(address lpToken)
        external
        virtual
        returns (address[10] memory tokens, uint256[10] memory amounts)
    {}

    function getPid(address lpToken) external view virtual returns (PidsInfo memory) {}
}
