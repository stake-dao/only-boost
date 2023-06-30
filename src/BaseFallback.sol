// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

// --- Solmate Contracts
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/**
 * @title BaseFallback
 * @author Stake DAO
 * @notice Base contract for fallback implementation for Stake DAO Strategies
 * @dev Inherit from Solmate `Auth` implementation
 */
contract BaseFallback is Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    //////////////////////////////////////////////////////
    /// --- STRUCTS
    //////////////////////////////////////////////////////
    // Struct to store pool ids from ConvexCurve or ConvexFrax
    struct PidsInfo {
        uint256 pid; // Pool id from ConvexCurve or ConvexFrax
        bool isInitialized; // Flag to check if pool is initialized internally
    }

    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////
    // --- ERC20
    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ERC20 public constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////
    // --- Addresses
    address public curveStrategy; // Address of Stake DAO curve strategy
    address public feeReceiver = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063; // Address to receive fees, MS Stake DAO

    // --- Uints
    uint256 public lastPidsCount; // Number of pools on ConvexCurve or ConvexFrax
    uint256 public rewardFee; // Fees to be collected from the strategy, in WAD unit

    // --- Mappings
    mapping(address => PidsInfo) public pids; // lpToken address --> pool ids from ConvexCurve or ConvexFrax

    //////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////
    event Deposited(address token, uint256 amount);
    event Withdrawn(address token, uint256 amount);
    event ClaimedRewards(address rewardToken, uint256 amountClaimed);

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////
    constructor(address owner, Authority _authority, address _curveStrategy) Auth(owner, _authority) {
        curveStrategy = _curveStrategy;

        // Set all the pid mapping
        setAllPidsOptimized();
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////
    /**
     * @notice Set fees on rewards new value
     * @param _feesOnRewards Value of new fees on rewards, in WAD unit
     */
    function setFeesOnRewards(uint256 _feesOnRewards) external requiresAuth {
        rewardFee = _feesOnRewards;
    }

    /**
     * @notice Set fees receiver new address
     * @param _feesReceiver Address of new fees receiver
     */
    function setFeesReceiver(address _feesReceiver) external requiresAuth {
        feeReceiver = _feesReceiver;
    }

    /**
     * @notice Rescue lost ERC20 tokens from contract
     * @param token Addresss of token to rescue
     * @param to Address to send rescued tokens to
     * @param amount Amount of token to rescue
     */
    function rescueERC20(address token, address to, uint256 amount) external requiresAuth {
        // Transfer `amount` of `token` to `to`
        ERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Internal process to handle rewards
     * @param rewardsTokens Array of address containing rewards tokens to handle
     * @return Array of uint256 containing amounts of rewards tokens remaining after fees
     */
    function _handleRewards(address[] memory rewardsTokens) internal returns (uint256[] memory) {
        uint256[] memory amountsRewards = new uint256[](rewardsTokens.length);

        // Cache extra rewards tokens length
        uint256 extraRewardsLength = rewardsTokens.length;
        // Transfer extra rewards to strategy if any
        if (extraRewardsLength > 0) {
            for (uint8 i = 0; i < extraRewardsLength;) {
                // Cache extra rewards token balance
                amountsRewards[i] = _distributeRewardToken(rewardsTokens[i]);

                // No need to check for overflows
                unchecked {
                    ++i;
                }
            }
        }

        return amountsRewards;
    }

    /**
     * @notice Internal process to distribute rewards
     * @dev Distribute rewards to strategy and charge fees
     * @param token Address of token to distribute
     * @return Amount of token distributed
     */
    function _distributeRewardToken(address token) internal returns (uint256) {
        // Transfer CRV rewards to strategy and charge fees
        uint256 _tokenBalance = ERC20(token).balanceOf(address(this));

        // If there is reward token to distribute
        if (_tokenBalance > 0) {
            // If there is a fee to be collected
            if (rewardFee > 0) {
                // Calculate fee amount
                uint256 feeAmount = _tokenBalance.mulWadDown(rewardFee);
                _tokenBalance -= feeAmount;
                // Transfer fee to fee receiver
                ERC20(token).safeTransfer(feeReceiver, feeAmount);
            }

            // Transfer rewards to strategy
            ERC20(token).safeTransfer(curveStrategy, _tokenBalance);
        }

        emit ClaimedRewards(token, _tokenBalance);

        return _tokenBalance;
    }

    //////////////////////////////////////////////////////
    /// --- VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////
    function setAllPidsOptimized() public virtual {}

    function isActive(address lpToken) external view virtual returns (bool) {}

    function balanceOf(address lpToken) public view virtual returns (uint256) {}

    function deposit(address lpToken, uint256 amount) external virtual {}

    function withdraw(address lpToken, uint256 amount) external virtual {}

    function claimRewards(address lpToken) external virtual returns (address[] memory, uint256[] memory) {}

    function getRewardsTokens(address lpToken) public view virtual returns (address[] memory) {}

    function getPid(address lpToken) external view virtual returns (PidsInfo memory) {}
}
