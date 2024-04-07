// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title A contract that receive reward tokens from Strategies on harvest, and split them according to the fee structure specified (per Accumulator)
/// @author StakeDAO
contract FeeReceiver {
    struct Repartition {
        uint256 dao;
        uint256 accumulator;
        uint256 veSdtFeeProxy;
    }

    /// @notice governance
    address public governance;

    /// @notice future governance
    address public futureGovernance;

    /// @notice dao address
    address public dao;

    /// @notice veSdtFeeProxy address
    address public veSdtFeeProxy;

    /// @notice Base fee (10_000 = 100%)
    uint256 private constant BASE_FEE = 10_000;

    /// @notice Accumulator => Reward token
    /// @dev Allows multiple strategies to use that contract
    mapping(address accumulator => address rewardToken) public accumulatorRewardToken;

    /// @notice Accumulator => Repartition structure
    /// @dev Each accumulator/rewardToken can have a specific fee structure
    mapping(address accumulator => Repartition) public accumulatorRepartition;

    ////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS ---
    ////////////////////////////////////////////////////////////

    /// @notice Event emitted when the reward token is split between the different parties
    /// @param accumulator accumulator address
    /// @param rewardToken reward token address
    /// @param daoPart dao part
    /// @param accumulatorPart accumulator part
    /// @param veSdtFeeProxyPart veSdtFeeProxy part
    event Split(
        address indexed accumulator,
        address indexed rewardToken,
        uint256 daoPart,
        uint256 accumulatorPart,
        uint256 veSdtFeeProxyPart
    );

    /// @notice Event emitted when a new future governance has set
    event TransferGovernance(address futureGovernance);

    /// @notice Event emitted when the future governance accepts to be the governance
    event GovernanceChanged(address governance);

    /// @notice Error emitted when an onlyGovernance function has called by a different address
    error GOVERNANCE();

    /// @notice Error emitted when an onlyFutureGovernance function has called by a different address
    error FUTURE_GOVERNANCE();

    /// @notice Error emitted when a zero address is pass
    error ZERO_ADDRESS();

    /// @notice Error emitted when the accumulator is not setted
    error UNKNOWN_ACCUMULATOR();

    /// @notice Error emitted when the repartition is not setted for the accumulator
    error REPARTITION_NOT_SET();

    /// @notice Error emitted when the total setted fee is invalid (not equal to 100%)
    error INVALID_FEE();

    //////////////////////////////////////////////////////
    /// --- MODIFIERS
    //////////////////////////////////////////////////////

    /// @notice Modifier to check if the caller is the governance
    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    /// @notice Modifier to check if the caller is the future governance
    modifier onlyFutureGovernance() {
        if (msg.sender != futureGovernance) revert FUTURE_GOVERNANCE();
        _;
    }

    constructor(address _governance, address _veSdtFeeProxy, address _dao) {
        if (_veSdtFeeProxy == address(0) || _dao == address(0)) revert ZERO_ADDRESS();
        governance = _governance; 
        dao = _dao;
        veSdtFeeProxy = _veSdtFeeProxy;
    }

    /// @notice Split the token between the different parties
    /// @dev Only an accumulator can call this function
    /// @dev Reward token address is taken from the mapping, if not found, revert
    function split() external {
        address rewardToken = accumulatorRewardToken[msg.sender];

        // If the reward token is not set, for the msg.sender revert
        if (rewardToken == address(0)) {
            revert UNKNOWN_ACCUMULATOR();
        }

        Repartition memory repartition = accumulatorRepartition[msg.sender];

        // If the repartition is not set, for the msg.sender revert
        if (repartition.dao == 0 && repartition.accumulator == 0 && repartition.veSdtFeeProxy == 0) {
            revert REPARTITION_NOT_SET();
        }

        // Can be some leftovers (rounding issues from prev split)
        uint256 totalBalance = ERC20(rewardToken).balanceOf(address(this));

        if (totalBalance == 0) {
            return;
        }

        uint256 daoPart;
        uint256 accumulatorPart;
        uint256 veSdtFeeProxyPart;

        // DAO part
        if (repartition.dao > 0) {
            daoPart = totalBalance * repartition.dao / BASE_FEE;
            SafeTransferLib.safeTransfer(rewardToken, dao, daoPart);
        }

        // veSdtFeeProxy part
        if (repartition.veSdtFeeProxy > 0) {
            veSdtFeeProxyPart = totalBalance * repartition.veSdtFeeProxy / BASE_FEE;
            SafeTransferLib.safeTransfer(rewardToken, veSdtFeeProxy, veSdtFeeProxyPart);
        }

        // Accumulator part
        if (repartition.accumulator > 0) {
            accumulatorPart = totalBalance * repartition.accumulator / BASE_FEE;
            SafeTransferLib.safeTransfer(rewardToken, msg.sender, accumulatorPart);
        }

        emit Split(msg.sender, rewardToken, daoPart, accumulatorPart, veSdtFeeProxyPart);
    }

    //////////////////////////////////////////////////////
    /// --- GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Set a new future governance that can accept it
    /// @dev Can be called only by the governance
    /// @param _futureGovernance future governance address
    function transferGovernance(address _futureGovernance) external onlyGovernance {
        if (_futureGovernance == address(0)) revert ZERO_ADDRESS();
        futureGovernance = _futureGovernance;
        emit TransferGovernance(_futureGovernance);
    }

    /// @notice Accept the governance
    /// @dev Can be called only by future governance
    function acceptGovernance() external onlyFutureGovernance {
        governance = futureGovernance;
        futureGovernance = address(0);
        emit GovernanceChanged(governance);
    }

    /// @notice Set both the reward token and the repartition for the accumulator
    /// @dev Can be called only by the governance
    /// @dev Will override the previous reward token and repartition if already set
    /// @param accumulator accumulator address
    /// @param rewardToken reward token address
    /// @param daoPart dao part
    /// @param accumulatorPart accumulator part
    /// @param veSdtFeeProxyPart veSdtFeeProxy part
    function setRewardTokenAndRepartition(
        address accumulator,
        address rewardToken,
        uint256 daoPart,
        uint256 accumulatorPart,
        uint256 veSdtFeeProxyPart
    ) external onlyGovernance {
        if (accumulator == address(0) || rewardToken == address(0)) revert ZERO_ADDRESS();
        if (daoPart + accumulatorPart + veSdtFeeProxyPart != BASE_FEE) revert INVALID_FEE();

        accumulatorRewardToken[accumulator] = rewardToken;
        accumulatorRepartition[accumulator] = Repartition(daoPart, accumulatorPart, veSdtFeeProxyPart);
    }

    /// @notice Set the repartition for the accumulator
    /// @dev Can be called only by the governance
    /// @param accumulator accumulator address
    /// @param daoPart dao part
    /// @param accumulatorPart accumulator part
    /// @param veSdtFeeProxyPart veSdtFeeProxy part
    /// @dev Accumulator must be already set
    function setRepartition(address accumulator, uint256 daoPart, uint256 accumulatorPart, uint256 veSdtFeeProxyPart)
        external
        onlyGovernance
    {
        if (accumulatorRewardToken[accumulator] == address(0)) revert UNKNOWN_ACCUMULATOR();
        if (daoPart + accumulatorPart + veSdtFeeProxyPart != BASE_FEE) revert INVALID_FEE();

        accumulatorRepartition[accumulator] = Repartition(daoPart, accumulatorPart, veSdtFeeProxyPart);
    }

    /// @notice Set dao address
    /// @dev Can be called only by the governance
    /// @param _dao dao address
    function setDao(address _dao) external onlyGovernance {
        if (_dao == address(0)) revert ZERO_ADDRESS();
        dao = _dao;
    }

    /// @notice Set veSdtFeeProxy address
    /// @dev Can be called only by the governance
    /// @param _veSdtFeeProxy veSdtFeeProxy address
    function setVeSdtFeeProxy(address _veSdtFeeProxy) external onlyGovernance {
        if (_veSdtFeeProxy == address(0)) revert ZERO_ADDRESS();
        veSdtFeeProxy = _veSdtFeeProxy;
    }
}
