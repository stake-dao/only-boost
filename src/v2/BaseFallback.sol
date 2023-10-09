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

    // --- Structs
    /// @notice Struct to store fees
    /// @param perfFee Fee collected as performance fee
    /// @param accumulatorFee Fee collected for accumulator
    /// @param veSDTFee Fee collected for veSDT holders
    /// @param claimerRewardFee Fee collected for reward claimer
    struct Fees {
        uint256 perfFee;
        uint256 accumulatorFee;
        uint256 veSDTFee;
        uint256 claimerRewardFee;
        uint256 totalFee;
    }

    // --- Enums
    /// @notice Enum to store fee types
    /// @param PERF_FEE Performance fee
    /// @param VESDT_FEE veSDT fee
    /// @param ACCUMULATOR_FEE Accumulator fee
    /// @param CLAIMER_REWARD Claimer reward fee
    enum MANAGEFEE {
        PERF_FEE,
        VESDT_FEE,
        ACCUMULATOR_FEE,
        CLAIMER_REWARD
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

    // --- Addresses
    /// @notice Stake DAO Rewards Receiver
    address public rewardsReceiver = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    /// @notice Interface for Stake DAO CRV Accumulator
    address public accumulator = address(0xa44bFD194Fd7185ebecEcE4F7fA87a47DaA01c6A);

    /// @notice Stake DAO veSDT Proxy
    address public veSDTFeeProxy = 0x9592Ec0605CE232A4ce873C650d2Aa01c79cb69E;

    // --- Mappings
    /// @notice LP token address -> pool ids from ConvexCurve or ConvexFrax
    mapping(address => PidsInfo) public pids;

    /// @notice Map Stake DAO liquidity gauge -> Fees struct
    mapping(address => Fees) public feesInfos;

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

    /// @notice Emitted when a reward receiver is set
    /// @param _rewardsReceiver Address of the new rewards receiver
    event RewardsReceiverSet(address _rewardsReceiver);

    /// @notice Emitted when a new veSDT Proxy contract is set
    /// @param _veSDTProxy Address of the new veSDT Proxy contract
    event VeSDTProxySet(address _veSDTProxy);

    /// @notice Emitted when a new Stake DAO CRV Accumulator is set
    /// @param _accumulator Address of the new Stake DAO CRV Accumulator
    event AccumulatorSet(address _accumulator);

    /// @notice Emitted when fee are updated
    /// @param _manageFee New management fee
    /// @param _gauge Address of the Curve DAO liquidity gauge
    /// @param _fee New performance fee
    event FeeManaged(uint256 _manageFee, address _gauge, uint256 _fee);

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error emitted when input address is null
    error ADDRESS_NULL();

    /// @notice Error emitted when caller is not strategy
    error NOT_STRATEGY();

    /// @notice Error emitted when token is not active
    error NOT_VALID_PID();

    /// @notice Error emitted when sum of fees is above 100%
    error FEE_TOO_HIGH();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    modifier onlyStrategy() {
        if (msg.sender != curveStrategy) revert NOT_STRATEGY();
        _;
    }

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
            for (uint256 i; i < extraRewardsLength;) {
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
        Fees storage fee = feesInfos[gauge];
        if (fee.totalFee == 0) return rewardsBalance;

        uint256 veSDTPart;
        uint256 multisigFee;
        uint256 claimerPart;
        uint256 accumulatorPart;

        if (fee.perfFee > 0) {
            multisigFee = rewardsBalance.mulDivDown(fee.perfFee, 10_000);
            ERC20(rewardToken).safeTransfer(rewardsReceiver, multisigFee);
        }

        if (fee.accumulatorFee > 0) {
            accumulatorPart = rewardsBalance.mulDivDown(fee.accumulatorFee, 10_000);
            ERC20(rewardToken).safeApprove(address(accumulator), accumulatorPart);
            IAccumulator(accumulator).depositToken(rewardToken, accumulatorPart);
        }

        if (fee.veSDTFee > 0) {
            veSDTPart = rewardsBalance.mulDivDown(fee.veSDTFee, 10_000);
            ERC20(rewardToken).safeTransfer(veSDTFeeProxy, veSDTPart);
        }

        if (fee.claimerRewardFee > 0) {
            claimerPart = rewardsBalance.mulDivDown(fee.claimerRewardFee, 10_000);
            ERC20(rewardToken).safeTransfer(claimer, claimerPart);
        }

        return rewardsBalance - multisigFee - accumulatorPart - veSDTPart - claimerPart;
    }

    /// @notice Set new curve strategy address
    /// @param _curveStrategy Address of curve strategy
    function setCurveStrategy(address _curveStrategy) external requiresAuth {
        curveStrategy = _curveStrategy;
    }

    /// @notice Set VeSDTFeeProxy new address
    /// @param newVeSDTProxy Address of new VeSDTFeeProxy
    function setVeSDTProxy(address newVeSDTProxy) external requiresAuth {
        if (newVeSDTProxy == address(0)) revert ADDRESS_NULL();
        veSDTFeeProxy = newVeSDTProxy;
        emit VeSDTProxySet(newVeSDTProxy);
    }

    /// @notice Set Accumulator new address
    /// @param newAccumulator Address of new Accumulator
    function setAccumulator(address newAccumulator) external requiresAuth {
        if (newAccumulator == address(0)) revert ADDRESS_NULL();
        accumulator = newAccumulator;
        emit AccumulatorSet(newAccumulator);
    }

    /// @notice Set RewardsReceiver new address
    /// @param newRewardsReceiver Address of new RewardsReceiver
    function setRewardsReceiver(address newRewardsReceiver) external requiresAuth {
        if (newRewardsReceiver == address(0)) revert ADDRESS_NULL();
        rewardsReceiver = newRewardsReceiver;
        emit RewardsReceiverSet(newRewardsReceiver);
    }

    /// @notice Set fees for a Liquidity gauge
    /// @param manageFee_ Enum for the fee to set
    /// @param gauge Address of Liquidity gauge
    /// @param newFee New fee to set
    function manageFee(MANAGEFEE manageFee_, address gauge, uint256 newFee) external requiresAuth {
        if (gauge == address(0)) revert ADDRESS_NULL();

        Fees storage feesInfo = feesInfos[gauge];

        if (manageFee_ == MANAGEFEE.PERF_FEE) {
            // 0
            feesInfo.perfFee = newFee;
        } else if (manageFee_ == MANAGEFEE.VESDT_FEE) {
            // 1
            feesInfo.veSDTFee = newFee;
        } else if (manageFee_ == MANAGEFEE.ACCUMULATOR_FEE) {
            //2
            feesInfo.accumulatorFee = newFee;
        } else if (manageFee_ == MANAGEFEE.CLAIMER_REWARD) {
            // 3
            feesInfo.claimerRewardFee = newFee;
        }

        uint256 _totalFee = feesInfo.perfFee + feesInfo.veSDTFee + feesInfo.accumulatorFee + feesInfo.claimerRewardFee;

        if (_totalFee > 10_000) {
            revert FEE_TOO_HIGH();
        }

        feesInfo.totalFee = _totalFee;
        emit FeeManaged(uint256(manageFee_), gauge, newFee);
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

    function getPid(address token) public view virtual returns (PidsInfo memory) {}
}
