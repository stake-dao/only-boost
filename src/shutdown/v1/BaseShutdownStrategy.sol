// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IModuleManager} from "src/interfaces/IModuleManager.sol";

/// @title BaseShutdownStrategy
/// @author Stake DAO
/// @dev Provides shared functionality for handling GATEWAY and LOCKER relationships
abstract contract BaseShutdownStrategy is Ownable2Step {
    using Math for uint256;
    using SafeERC20 for IERC20;

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    /// @notice The locker contract address
    address public immutable LOCKER;

    /// @notice The gateway contract address
    address public immutable GATEWAY;

    /// @notice The default protocol fee.
    /// @dev The validity of this value is not checked. It must always be valid
    uint128 internal constant DEFAULT_PROTOCOL_FEE = 0.15e18;

    /// @notice The default harvest fee.
    /// @dev The validity of this value is not checked. It must always be valid
    uint128 internal constant DEFAULT_HARVEST_FEE = 0.005e18;

    /// @notice Address of the fee recipient.
    address public feeRecipient;

    /// @notice The amount of protocol fees accrued.
    uint256 public protocolFeesAccrued;

    /// @notice Whether the gauge is shutdown
    mapping(address => bool) public isShutdown;

    /// @notice Mapping of protected gauges.
    mapping(address => bool) public protectedGauges;

    /// @notice Error when the gauge is shutdown
    error SHUTDOWN();

    /// @notice Error when the gauge is not set
    error ADDRESS_ZERO();

    /// @notice Event when protocol fees are claimed
    event ProtocolFeesClaimed(uint256 amount);

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    /// @notice Initializes the base contract with protocol ID, controller, locker, and gateway
    /// @param _locker The locker contract address (can be zero, in which case GATEWAY is used)
    /// @param _gateway The gateway contract address
    /// @param _governance The governance address
    constructor(address _locker, address _gateway, address _governance) Ownable() {
        LOCKER = _locker;
        GATEWAY = _gateway;

        _transferOwnership(_governance);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    /// @notice Set the protected gauges.
    /// @param _gauges The gauges to set as protected.
    function setProtectedGauges(address[] calldata _gauges) external onlyOwner {
        for (uint256 i = 0; i < _gauges.length; i++) {
            protectedGauges[_gauges[i]] = true;
        }
    }

    /// @notice Unset the protected gauges.
    /// @param _gauges The gauges to unset as protected.
    function unsetProtectedGauges(address[] calldata _gauges) external onlyOwner {
        for (uint256 i = 0; i < _gauges.length; i++) {
            protectedGauges[_gauges[i]] = false;
        }
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    function _chargeProtocolFees(address _token, uint256 _minted) internal returns (uint256 net) {
        /// 1. Calculate the protocol fee.
        uint256 protocolFee = _minted.mulDiv(DEFAULT_PROTOCOL_FEE, 1e18);

        /// 2. Calculate the harvest fee.
        uint256 harvestFee = _minted.mulDiv(DEFAULT_HARVEST_FEE, 1e18);

        /// 3. Calculate the net amount.
        net = _minted - protocolFee - harvestFee;

        /// 4. Update the protocol fees accrued.
        protocolFeesAccrued += protocolFee;

        /// 5. Transfer the harvest fee to the fee recipient.
        IERC20(_token).safeTransfer(msg.sender, harvestFee);
    }

    /// @notice Claims accumulated protocol fees.
    /// @dev Transfers fees to the configured fee receiver.
    /// @custom:throws NoFeeReceiver If the fee receiver is not set.
    function _claimProtocolFees(address _token) internal {
        if (feeRecipient == address(0)) revert ADDRESS_ZERO();

        // get the protocol fees accrued until now and reset the stored value
        uint256 currentAccruedProtocolFees = protocolFeesAccrued;

        protocolFeesAccrued = 0;

        // transfer the accrued protocol fees to the fee receiver and emit the claim event
        IERC20(_token).safeTransfer(feeRecipient, currentAccruedProtocolFees);

        emit ProtocolFeesClaimed(currentAccruedProtocolFees);
    }

    /// @notice Executes a transaction through the gateway/module manager
    /// @dev Handles the common pattern of executing transactions through the gateway/module manager
    ///      based on whether LOCKER is the same as GATEWAY
    /// @param target The address of the contract to interact with
    /// @param data The calldata to send to the target
    function _executeTransaction(address target, bytes memory data) internal returns (bool success) {
        // Otherwise execute through the locker's execute function
        success = IModuleManager(GATEWAY).execTransactionFromModule(
            LOCKER,
            0,
            abi.encodeWithSignature("execute(address,uint256,bytes)", target, 0, data),
            IModuleManager.Operation.Call
        );
    }
}
