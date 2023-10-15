// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IBooster} from "src/interfaces/IBooster.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";
import {IFallback} from "src/interfaces/IFallback.sol";

/// @notice Minimal proxy factory for ConvexFallback contract.
contract ConvexMinimalProxyFactory {
    using LibClone for address;

    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Convex like booster contract address.
    address public immutable booster;
    /// @notice Stake DAO strategy contract address.
    address public immutable strategy;

    /// @notice Reward token address.
    address public immutable rewardToken;
    /// @notice Fallback reward token address.
    address public immutable fallbackRewardToken;

    /// @notice ConvexFallback implementation address.
    address public immutable implementation;

    /// @notice Address of the governance.
    address public governance;

    /// @notice Address of the future governance contract.
    address public futureGovernance;

    /// @notice Percentage of fees charged on `rewardToken` claimed.
    uint256 public protocolFeesPercent;

    /// @notice Mapping of gauges to fallbacks.
    mapping(address => address) public fallbacks;

    /// @notice Error emitted when auth failed
    error GOVERNANCE();

    /// @notice Error emitted when sum of fees is above 100%
    error FEE_TOO_HIGH();

    /// @notice Event emitted when governance is changed.
    /// @param newGovernance Address of the new governance.
    event GovernanceChanged(address indexed newGovernance);

    modifier onlyGovernance() {
        if (msg.sender != governance) revert GOVERNANCE();
        _;
    }

    constructor(
        address _booster,
        address _strategy,
        address _rewardToken,
        address _fallbackRewardToken,
        address _implementation
    ) {
        governance = msg.sender;

        booster = _booster;
        strategy = _strategy;
        rewardToken = _rewardToken;
        fallbackRewardToken = _fallbackRewardToken;

        implementation = _implementation;
    }

    /// @notice Create a new ConvexFallback contract
    /// @param _token LP token address
    /// @param _pid Pool id from Convex
    /// @return _fallback New ConvexFallback contract address
    function create(address _token, uint256 _pid) external returns (address _fallback) {
        /// Check if the pool id is valid
        require(IBooster(booster).poolLength() > _pid, "INVALID_PID");

        /// Check if the LP token is valid
        (address lpToken,, address gauge, address _baseRewardPool,, bool isShutdown) = IBooster(booster).poolInfo(_pid);

        require(!isShutdown, "SHUTDOWN");
        require(lpToken == _token, "INVALID_TOKEN");

        bytes memory data = abi.encodePacked(
            address(this), _token, rewardToken, fallbackRewardToken, strategy, booster, _baseRewardPool, _pid
        );

        bytes32 salt = keccak256(abi.encodePacked(_token, _pid));
        // Clone the implementation
        _fallback = implementation.cloneDeterministic(data, salt);

        /// Initialize the contract.
        IFallback(_fallback).initialize();

        /// Set the fallback contract in the mapping.
        fallbacks[gauge] = _fallback;
    }

    /// @notice Update protocol fees.
    /// @param _protocolFee New protocol fee.
    function updateProtocolFee(uint256 _protocolFee) external onlyGovernance {
        if (_protocolFee > DENOMINATOR) revert FEE_TOO_HIGH();
        protocolFeesPercent = _protocolFee;
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
}
