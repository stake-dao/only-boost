// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title A contract that receive reward tokens from Strategies on harvest, and split them according to the fee structure specified (per reward token)
/// @author StakeDAO
contract RewardSplitter {
    /// @notice Repartition struct
    /// @param receivers array of receivers
    /// @param fees array of fees
    /// @dev First go to the first receiver, then the second, and so on
    /// @dev Fee in basis points, where 10,000 basis points = 100%
    struct Repartition {
        address[] receivers;
        uint256[] fees; // Fee in basis points, where 10,000 basis points = 100%
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

    /// @notice Reward token -> Repartition
    mapping(address => Repartition) private rewardTokenRepartition;

    ////////////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS ---
    ////////////////////////////////////////////////////////////

    /// @notice Event emitted when the reward token is splitted between the different parties
    /// @param rewardToken reward token address
    /// @param repartition repartition struct
    event Split(address indexed rewardToken, Repartition repartition);

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

    /// @notice Error emitted when the distribution is not setted for the reward token
    error DISTRIBUTION_NOT_SET();

    /// @notice Error emitted when the total setted fee is invalid (not equal to 100%)
    error INVALID_FEE();

    /// @notice Error emitted when the repartition is invalid
    error INVALID_REPARTITION();

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

    constructor(address _governance) {
        governance = _governance;
    }

    ////////////////////////////////////////////////////////////
    /// --- VIEW FUNCTIONS ---
    ////////////////////////////////////////////////////////////

    function getRepartition(address rewardToken)
        external
        view
        returns (address[] memory receivers, uint256[] memory fees)
    {
        Repartition memory repartition = rewardTokenRepartition[rewardToken];
        return (repartition.receivers, repartition.fees);
    }

    /// @notice Split the token between the different parties
    /// @param rewardToken reward token address
    /// @dev Splitting for that accumulator
    /// @dev Reward token address is taken from the mapping, if not found, revert
    function split(address rewardToken) external {
        Repartition memory repartition = rewardTokenRepartition[rewardToken];

        uint256 length = repartition.receivers.length;
        address[] memory receivers = repartition.receivers;
        uint256[] memory fees = repartition.fees;

        // If repartition are not set, revert
        if (length == 0) {
            revert DISTRIBUTION_NOT_SET();
        }

        uint256 totalBalance = ERC20(rewardToken).balanceOf(address(this));

        if (totalBalance == 0) {
            return;
        }

        for (uint256 i = 0; i < length; i++) {
            uint256 fee = totalBalance * fees[i] / BASE_FEE;
            SafeTransferLib.safeTransfer(rewardToken, receivers[i], fee);
        }

        emit Split(rewardToken, repartition);
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

    /// @notice Set repartition for a reward token
    /// @dev Can be called only by the governance
    /// @dev Will override the previous reward token and distribution if already set
    /// @param rewardToken reward token address
    /// @param receivers array of receivers
    /// @param fees array of fees
    function setRepartition(address rewardToken, address[] calldata receivers, uint256[] calldata fees) external onlyGovernance {
        if (rewardToken == address(0)) revert ZERO_ADDRESS();

        if (receivers.length == 0 || receivers.length != fees.length) revert INVALID_REPARTITION();

        // Check that sum of fees is 100%
        uint256 totalFee = 0;

        for (uint256 i = 0; i < receivers.length; i++) {
            totalFee += fees[i];
        }

        if (totalFee != BASE_FEE) revert INVALID_FEE();

        rewardTokenRepartition[rewardToken] = Repartition(receivers, fees);
    }
}
