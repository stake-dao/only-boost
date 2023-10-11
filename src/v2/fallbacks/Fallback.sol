// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

/// @title BaseFallback
/// @author Stake DAO
/// @notice Base contract for fallback implementation for Stake DAO Strategies
abstract contract Fallback {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Struct to store pool ids from Convex
    /// @param pid Pool id from Convex
    /// @param isInitialized Flag to check if pool is initialized
    struct Pid {
        uint256 pid;
        bool isInitialized;
    }

    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Address of the strategy proxy contract.
    address public immutable strategy;

    /// @notice Address of the token being rewarded.
    address public immutable rewardToken;

    /// @notice Address of the extra token being rewarded by the fallback.
    /// @dev EG. CVX for Convex, Aura for Aura.
    address public immutable fallbackRewardToken;

    /// @notice Address of the governance.
    address public governance;

    /// @notice Address of the future governance contract.
    address public futureGovernance;

    /// @notice Address accruing protocol fees.
    address public feeReceiver;

    /// @notice Percentage of fees charged on `rewardToken` claimed.
    uint256 public protocolFeesPercent;

    /// @notice Amount of fees charged on `rewardToken` claimed
    uint256 public feesAccrued;

    /// @notice Percentage of fees charged on `rewardToken` claimed to incentivize claimers.
    uint256 public claimIncentiveFee;

    /// @notice Counter for pool ids from Convex in use.
    uint256 public lastPid;

    /// @notice LP token address -> pool ids from ConvexCurve or ConvexFrax
    mapping(address => Pid) public pids;

    //////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    //////////////////////////////////////////////////////

    /// @notice Emitted when a token is deposited
    /// @param token Address of token deposited
    /// @param amount Amount of token deposited
    event Deposited(address token, uint256 amount);

    /// @notice Emitted when a token is withdrawn
    /// @param token Address of token withdrawn
    /// @param amount Amount of token withdrawn
    event Withdrawn(address token, uint256 amount);

    /// @notice Event emitted when governance is changed.
    /// @param newGovernance Address of the new governance.
    event GovernanceChanged(address indexed newGovernance);

    /// @notice Error emitted when input address is null
    error ADDRESS_NULL();

    /// @notice Error emitted when token is not active
    error NOT_VALID_PID();

    /// @notice Error emitted when sum of fees is above 100%
    error FEE_TOO_HIGH();

    /// @notice Error emitted when caller is not strategy
    error STRATEGY();

    /// @notice Error emitted when caller is not governance
    error GOVERNANCE();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    modifier onlyStrategy() {
        if (msg.sender != strategy) revert STRATEGY();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor(address _governance, address _token, address _fallbackRewardToken, address _strategy) {
        governance = _governance;

        rewardToken = _token;
        fallbackRewardToken = _fallbackRewardToken;

        strategy = _strategy;
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Internal function to charge protocol fees from `rewardToken` claimed by the locker.
    function _chargeProtocolFees(uint256 _amount) internal view returns (uint256, uint256) {
        if (_amount == 0) return (0, 0);
        if (protocolFeesPercent == 0) return (_amount, 0);

        uint256 _feeAccrued = _amount.mulDivDown(protocolFeesPercent, DENOMINATOR);

        return (_amount - _feeAccrued, _feeAccrued);
    }

    /// @notice Transfer the governance to a new address.
    /// @param _governance Address of the new governance.
    function transferGovernance(address _governance) external onlyGovernance {
        futureGovernance = _governance;
    }

    /// @notice Accept the governance transfer.
    function acceptGovernance() external {
        if (msg.sender != futureGovernance) revert GOVERNANCE();

        governance = msg.sender;
        emit GovernanceChanged(msg.sender);
    }

    //////////////////////////////////////////////////////
    /// --- VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////

    function balanceOf(address token) public view virtual returns (uint256) {}

    function deposit(address token, uint256 amount) external virtual {}

    function withdraw(address token, uint256 amount) external virtual {}
}
