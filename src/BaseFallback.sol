// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

// --- Solmate Contracts
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// --- Interfaces
import {IAccumulator} from "src/interfaces/IAccumulator.sol";
import {ICurveStrategy} from "src/interfaces/ICurveStrategy.sol";

/// @title BaseFallback
/// @author Stake DAO
/// @notice Base contract for fallback implementation for Stake DAO Strategies
/// @dev Inherit from Solmate `Auth` implementation
contract BaseFallback is Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    //////////////////////////////////////////////////////
    /// --- STRUCTS
    //////////////////////////////////////////////////////

    /// @notice Struct to store pool ids from ConvexCurve or ConvexFrax
    /// @param pid Pool id from ConvexCurve or ConvexFrax
    /// @param isInitialized Flag to check if pool is initialized internally
    struct PidsInfo {
        uint256 pid;
        bool isInitialized;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTANTS
    //////////////////////////////////////////////////////

    // --- ERC20
    /// @notice Curve DAO ERC20 CRV Token
    ERC20 public constant CRV = ERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    /// @notice Convex ERC20 CVX Token
    ERC20 public constant CVX = ERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////

    // --- Addresses
    /// @notice Curve Strategy address
    address public curveStrategy;

    // --- Uints
    /// @notice Number of pools on ConvexCurve or ConvexFrax
    uint256 public lastPidsCount;

    // --- Mappings
    /// @notice LP token address -> pool ids from ConvexCurve or ConvexFrax
    mapping(address => PidsInfo) public pids;

    //////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////

    /// @notice Emitted when a token is deposited
    /// @param token Address of token deposited
    /// @param amount Amount of token deposited
    event Deposited(address token, uint256 amount);

    /// @notice Emitted when a token is withdrawn
    /// @param token Address of token withdrawn
    /// @param amount Amount of token withdrawn
    event Withdrawn(address token, uint256 amount);

    /// @notice Emitted when a reward is claimed
    /// @param rewardToken Address of reward token claimed
    /// @param amountClaimed Amount of reward token claimed
    event ClaimedRewards(address rewardToken, uint256 amountClaimed);

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor(address owner, Authority _authority, address _curveStrategy) Auth(owner, _authority) {
        curveStrategy = _curveStrategy;

        // Set all the pid mapping
        _setAllPidsOptimized();
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Rescue lost ERC20 tokens from contract
    /// @param token Addresss of token to rescue
    /// @param to Address to send rescued tokens to
    /// @param amount Amount of token to rescue
    function rescueERC20(address token, address to, uint256 amount) external requiresAuth {
        // Transfer `amount` of `token` to `to`
        ERC20(token).safeTransfer(to, amount);
    }

    /// @notice Internal process to handle rewards
    /// @param rewardsTokens Array of address containing rewards tokens to handle
    /// @param claimer Address of claimer
    /// @return Array of uint256 containing amounts of rewards tokens remaining after fees
    function _handleRewards(address token, address[] memory rewardsTokens, address claimer)
        internal
        returns (uint256[] memory)
    {
        uint256[] memory amountsRewards = new uint256[](rewardsTokens.length);

        // Cache extra rewards tokens length
        uint256 extraRewardsLength = rewardsTokens.length;
        // Transfer extra rewards to strategy if any
        if (extraRewardsLength > 0) {
            for (uint8 i = 0; i < extraRewardsLength;) {
                // Cache extra rewards token balance
                amountsRewards[i] = _distributeRewardToken(token, rewardsTokens[i], claimer);

                // No need to check for overflows
                unchecked {
                    ++i;
                }
            }
        }

        return amountsRewards;
    }

    /// @notice Internal process to distribute rewards
    /// @dev Distribute rewards to strategy and charge fees
    /// @param token Address of token to distribute
    /// @param claimer Address of claimer
    /// @return Amount of token distributed
    function _distributeRewardToken(address lpToken, address token, address claimer) internal returns (uint256) {
        // Transfer CRV rewards to strategy and charge fees
        uint256 _tokenBalance = ERC20(token).balanceOf(address(this));

        // If there is reward token to distribute
        if (_tokenBalance > 0) {
            // Take fees only on CRV rewards
            if (token == address(CRV)) {
                // Get gauge address form curve strategy
                address gauge = ICurveStrategy(curveStrategy).gauges(lpToken);

                // Send fees
                _tokenBalance = _sendFee(gauge, token, _tokenBalance, claimer);
            }

            // Transfer rewards to strategy
            ERC20(token).safeTransfer(curveStrategy, _tokenBalance);
        }

        emit ClaimedRewards(token, _tokenBalance);

        return _tokenBalance;
    }

    /// @notice Internal process to send fees from rewards
    /// @param gauge Address of Liqudity gauge corresponding to LP token
    /// @param rewardToken Address of reward token
    /// @param rewardsBalance Amount of reward token
    /// @param claimer Address of claimer
    /// @return Amount of reward token remaining
    function _sendFee(address gauge, address rewardToken, uint256 rewardsBalance, address claimer)
        internal
        returns (uint256)
    {
        // Fetch fees amount and fees receiver from curve strategy
        (ICurveStrategy.Fees memory fee, address accumulator, address rewardsReceiver, address veSDTFeeProxy) =
            ICurveStrategy(curveStrategy).getFeesAndReceiver(gauge);

        // calculate the amount for each fee recipient
        uint256 multisigFee = rewardsBalance.mulDivDown(fee.perfFee, 10_000);
        uint256 accumulatorPart = rewardsBalance.mulDivDown(fee.accumulatorFee, 10_000);
        uint256 veSDTPart = rewardsBalance.mulDivDown(fee.veSDTFee, 10_000);
        uint256 claimerPart = claimer != address(0) ? rewardsBalance.mulDivDown(fee.claimerRewardFee, 10_000) : 0;

        // send
        ERC20(rewardToken).safeApprove(address(accumulator), accumulatorPart);
        IAccumulator(accumulator).depositToken(rewardToken, accumulatorPart);
        ERC20(rewardToken).safeTransfer(rewardsReceiver, multisigFee);
        ERC20(rewardToken).safeTransfer(veSDTFeeProxy, veSDTPart);
        ERC20(rewardToken).safeTransfer(claimer, claimerPart);

        // Return remaining
        return rewardsBalance - multisigFee - accumulatorPart - veSDTPart - claimerPart;
    }

    /// @notice Set new curve strategy address
    /// @param _curveStrategy Address of curve strategy
    function setCurveStrategy(address _curveStrategy) external requiresAuth {
        curveStrategy = _curveStrategy;
    }

    //////////////////////////////////////////////////////
    /// --- VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////

    function setAllPidsOptimized() public virtual {}

    function _setAllPidsOptimized() internal virtual {}

    function isActive(address token) external view virtual returns (bool) {}

    function balanceOf(address token) public view virtual returns (uint256) {}

    function deposit(address token, uint256 amount) external virtual {}

    function withdraw(address token, uint256 amount) external virtual {}

    function claimRewards(address token, address claimer)
        external
        virtual
        returns (address[] memory, uint256[] memory)
    {}

    function getRewardsTokens(address token) public view virtual returns (address[] memory) {}

    function getPid(address token) external view virtual returns (PidsInfo memory) {}
}
