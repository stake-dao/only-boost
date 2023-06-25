// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract BaseFallback is Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    struct PidsInfo {
        uint256 pid;
        bool isInitialized;
    }

    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    uint256 public lastPidsCount; // Number of pools on ConvexCurve or ConvexFrax
    uint256 public rewardFee; // Fees to be collected from the strategy, in WAD unit

    address public curveStrategy;
    address public feeReceiver = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063; // Address to receive fees, MS Stake DAO

    mapping(address => PidsInfo) public pids; // lpToken address --> pool ids from ConvexCurve or ConvexFrax

    event Deposited(address token, uint256 amount);
    event Withdrawn(address token, uint256 amount);
    event ClaimedRewards(address lpToken, address rewardToken, uint256 amountClaimed);

    constructor(address owner, Authority _authority, address _curveStrategy) Auth(owner, _authority) {
        curveStrategy = _curveStrategy;
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////
    function setFeesOnRewards(uint256 _feesOnRewards) external requiresAuth {
        rewardFee = _feesOnRewards;
    }

    function setFeesReceiver(address _feesReceiver) external requiresAuth {
        feeReceiver = _feesReceiver;
    }

    function _handleRewards(address lpToken, address[] calldata rewardsTokens) internal {
        // Transfer CRV rewards to strategy and charge fees
        _distributeRewardToken(lpToken, address(CRV));

        // Transfer CVX rewards to strategy and charge fees
        _distributeRewardToken(lpToken, address(CVX));

        // Cache extra rewards tokens length
        uint256 extraRewardsLength = rewardsTokens.length;
        // Transfer extra rewards to strategy if any
        if (extraRewardsLength > 0) {
            for (uint256 i = 0; i < extraRewardsLength; ++i) {
                // Cache extra rewards token balance
                _distributeRewardToken(lpToken, rewardsTokens[i]);
            }
        }
    }

    function rescueERC20(address token, address to, uint256 amount) external requiresAuth {
        ERC20(token).safeTransfer(to, amount);
    }

    function _distributeRewardToken(address lpToken, address token) internal {
        // Transfer CRV rewards to strategy and charge fees
        uint256 _tokenBalance = ERC20(token).balanceOf(address(this));
        if (_tokenBalance > 0) {
            if (rewardFee > 0) {
                uint256 feeAmount = _tokenBalance.mulWadDown(rewardFee);
                _tokenBalance -= feeAmount;
                ERC20(token).safeTransfer(feeReceiver, feeAmount);
            }
            ERC20(token).safeTransfer(curveStrategy, _tokenBalance);
        }

        emit ClaimedRewards(lpToken, token, _tokenBalance);
    }

    //////////////////////////////////////////////////////
    /// --- VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////
    function _setPid(uint256 index) internal virtual {}

    function setAllPidsOptimized() public virtual {}

    function isActive(address lpToken) external virtual returns (bool) {}

    function balanceOf(address lpToken) external view virtual returns (uint256) {}

    function deposit(address lpToken, uint256 amount) external virtual {}

    function withdraw(address lpToken, uint256 amount) external virtual {}

    function claimRewards(address lpToken, address[] calldata) external virtual {}

    function getRewardsTokens(address lpToken) public view virtual returns (address[] memory) {}

    function getPid(address lpToken) external view virtual returns (PidsInfo memory) {}
}
