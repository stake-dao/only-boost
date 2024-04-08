// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title A contract that receive reward tokens from Strategies on harvest, and distribute them according to the fee structure specified (per reward token)
/// @author StakeDAO
contract FeeDistributionReceiver {
    struct FeeDistribution {
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

    /// @notice Reward token => Accumulator
    /// @dev Allows multiple strategies to use that contract
    mapping(address rewardToken => address accumulator) public rewardTokenAccumulator;

    /// @notice Accumulator => Distribution structure
    /// @dev Each rewardToken can have a specific fee structure
    mapping(address rewardToken => FeeDistribution) public rewardTokenFeeDistribution;

    ////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS ---
    ////////////////////////////////////////////////////////////

    /// @notice Event emitted when the reward token is distributed between the different parties
    /// @param rewardToken reward token address
    /// @param accumulator accumulator address
    /// @param daoPart dao part
    /// @param accumulatorPart accumulator part
    /// @param veSdtFeeProxyPart veSdtFeeProxy part
    event Distributed(
        address indexed rewardToken,
        address indexed accumulator,
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
    error ACCUMULATOR_NOT_SET();

    /// @notice Error emitted when the distribution is not setted for the reward token
    error DISTRIBUTION_NOT_SET();

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

    /// @notice Distribute the token between the different parties
    /// @param rewardToken reward token address
    /// @dev Splitting for that accumulator
    /// @dev Reward token address is taken from the mapping, if not found, revert
    function distribute(address rewardToken) external {
        address accumulator = rewardTokenAccumulator[rewardToken];

        // If the accumulator is not set, revert
        if (accumulator == address(0)) {
            revert ACCUMULATOR_NOT_SET();
        }

        FeeDistribution memory distribution = rewardTokenFeeDistribution[rewardToken];

        // If the distribution is not set, for the msg.sender revert
        if (distribution.dao == 0 && distribution.accumulator == 0 && distribution.veSdtFeeProxy == 0) {
            revert DISTRIBUTION_NOT_SET();
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
        if (distribution.dao > 0) {
            daoPart = totalBalance * distribution.dao / BASE_FEE;
            SafeTransferLib.safeTransfer(rewardToken, dao, daoPart);
        }

        // veSdtFeeProxy part
        if (distribution.veSdtFeeProxy > 0) {
            veSdtFeeProxyPart = totalBalance * distribution.veSdtFeeProxy / BASE_FEE;
            SafeTransferLib.safeTransfer(rewardToken, veSdtFeeProxy, veSdtFeeProxyPart);
        }

        // Accumulator part
        if (distribution.accumulator > 0) {
            accumulatorPart = totalBalance * distribution.accumulator / BASE_FEE;
            SafeTransferLib.safeTransfer(rewardToken, accumulator, accumulatorPart);
        }

        emit Distributed(rewardToken, accumulator, daoPart, accumulatorPart, veSdtFeeProxyPart);
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

    /// @notice Set both the reward token and the distribution for the accumulator
    /// @dev Can be called only by the governance
    /// @dev Will override the previous reward token and distribution if already set
    /// @param rewardToken reward token address
    /// @param accumulator accumulator address
    /// @param daoPart dao part
    /// @param accumulatorPart accumulator part
    /// @param veSdtFeeProxyPart veSdtFeeProxy part
    function setRewardTokenAndDistribution(
        address rewardToken,
        address accumulator,
        uint256 daoPart,
        uint256 accumulatorPart,
        uint256 veSdtFeeProxyPart
    ) external onlyGovernance {
        if (rewardToken == address(0)) revert ZERO_ADDRESS();
        if (daoPart + accumulatorPart + veSdtFeeProxyPart != BASE_FEE) revert INVALID_FEE();

        rewardTokenAccumulator[rewardToken] = accumulator;
        rewardTokenFeeDistribution[rewardToken] = FeeDistribution(daoPart, accumulatorPart, veSdtFeeProxyPart);
    }

    /// @notice Set the distribution for the accumulator
    /// @dev Can be called only by the governance
    /// @param rewardToken reward token address
    /// @param daoPart dao part
    /// @param accumulatorPart accumulator part
    /// @param veSdtFeeProxyPart veSdtFeeProxy part
    /// @dev Reward token must be already set
    function setDistribution(address rewardToken, uint256 daoPart, uint256 accumulatorPart, uint256 veSdtFeeProxyPart)
        external
        onlyGovernance
    {
        if (rewardTokenAccumulator[rewardToken] == address(0)) revert ACCUMULATOR_NOT_SET();
        if (daoPart + accumulatorPart + veSdtFeeProxyPart != BASE_FEE) revert INVALID_FEE();

        rewardTokenFeeDistribution[rewardToken] = FeeDistribution(daoPart, accumulatorPart, veSdtFeeProxyPart);
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
