// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// --- Solmate Contracts
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// --- Interfaces
import {ISdToken} from "src/interfaces/ISdToken.sol";
import {ITokenMinter} from "src/interfaces/ITokenMinter.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";

/// @title Contract that accepts tokens and locks them
/// @author Stake DAO
contract CrvDepositor is Auth {
    using SafeTransferLib for ERC20;

    //////////////////////////////////////////////////////
    /// --- CONSTANTS & IMMUTABLES
    //////////////////////////////////////////////////////

    ERC20 public immutable TOKEN;
    address public immutable LOCKER;
    address public immutable MINTER;
    address public constant SD_VE_CRV = 0x478bBC744811eE8310B461514BDc29D03739084D;
    uint256 public constant FEE_DENOMINATOR = 10_000;

    //////////////////////////////////////////////////////
    /// --- VARIABLES
    //////////////////////////////////////////////////////

    address public gauge;

    uint256 public lockIncentive = 10; //incentive to users who spend gas to lock token
    uint256 public incentiveToken;

    //////////////////////////////////////////////////////
    /// --- EVENTS
    //////////////////////////////////////////////////////

    event Deposited(address indexed caller, address indexed user, uint256 amount, bool lock, bool stake);
    event IncentiveReceived(address indexed caller, uint256 amount);
    event TokenLocked(address indexed user, uint256 amount);
    event GovernanceChanged(address indexed newGovernance);
    event SdTokenOperatorChanged(address indexed newSdToken);
    event FeesChanged(uint256 newFee);

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor(address _token, address _locker, address _minter, address _owner, Authority _authority)
        Auth(_owner, _authority)
    {
        TOKEN = ERC20(_token);
        LOCKER = _locker;
        MINTER = _minter;
    }

    //////////////////////////////////////////////////////
    /// --- RESTRICTED FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Set the new operator for minting sdToken
    /// @dev Only callable by governance
    /// @param _operator operator address
    function setSdTokenOperator(address _operator) external requiresAuth {
        ISdToken(MINTER).setOperator(_operator);
        emit SdTokenOperatorChanged(_operator);
    }

    /// @notice Set the gauge to deposit token yielded
    /// @dev Only callable by governance
    /// @param _gauge gauge address
    function setGauge(address _gauge) external requiresAuth {
        gauge = _gauge;
    }

    /// @notice set the fees for locking incentive
    /// @dev Only callable by governance
    /// @param _lockIncentive contract must have tokens to lock
    function setFees(uint256 _lockIncentive) external requiresAuth {
        if (_lockIncentive <= 30) {
            lockIncentive = _lockIncentive;
            emit FeesChanged(_lockIncentive);
        }
    }

    //////////////////////////////////////////////////////
    /// --- MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Locks the tokens held by the contract
    /// @dev The contract must have tokens to lock
    function _lockToken() internal {
        uint256 tokenBalance = TOKEN.balanceOf(address(this));

        // If there is Token available in the contract transfer it to the LOCKER
        if (tokenBalance > 0) {
            TOKEN.safeTransfer(LOCKER, tokenBalance);
            emit TokenLocked(msg.sender, tokenBalance);
        }

        uint256 tokenBalanceStaker = TOKEN.balanceOf(LOCKER);
        // If the LOCKER has no tokens then return
        if (tokenBalanceStaker == 0) {
            return;
        }

        //ILocker(LOCKER).increaseAmount(tokenBalanceStaker);
    }

    /// @notice Lock tokens held by the contract
    /// @dev The contract must have Token to lock
    function lockToken() external {
        _lockToken();

        // If there is incentive available give it to the user calling lockToken
        if (incentiveToken > 0) {
            ITokenMinter(MINTER).mint(msg.sender, incentiveToken);
            emit IncentiveReceived(msg.sender, incentiveToken);
            incentiveToken = 0;
        }
    }

    /// @notice Deposit & Lock Token
    /// @dev User needs to approve the contract to transfer the token
    /// @param _amount The amount of token to deposit
    /// @param _lock Whether to lock the token
    /// @param _stake Whether to stake the token
    /// @param _user User to deposit for
    function deposit(uint256 _amount, bool _lock, bool _stake, address _user) public {
        require(_amount > 0, "!>0");
        require(_user != address(0), "!user");

        // If User chooses to lock Token
        if (_lock) {
            TOKEN.safeTransferFrom(msg.sender, LOCKER, _amount);
            _lockToken();

            if (incentiveToken > 0) {
                _amount = _amount + incentiveToken;
                emit IncentiveReceived(msg.sender, incentiveToken);
                incentiveToken = 0;
            }
        } else {
            //move tokens here
            TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
            //defer lock cost to another user
            uint256 callIncentive = (_amount * lockIncentive) / FEE_DENOMINATOR;
            _amount = _amount - callIncentive;
            incentiveToken = incentiveToken + callIncentive;
        }

        if (_stake && gauge != address(0)) {
            ITokenMinter(MINTER).mint(address(this), _amount);
            ERC20(MINTER).safeApprove(gauge, _amount);
            ILiquidityGauge(gauge).deposit(_amount, _user);
        } else {
            ITokenMinter(MINTER).mint(_user, _amount);
        }

        emit Deposited(msg.sender, _user, _amount, _lock, _stake);
    }

    /// @notice Deposits all the token of a user & locks them based on the options choosen
    /// @dev User needs to approve the contract to transfer Token tokens
    /// @param _lock Whether to lock the token
    /// @param _stake Whether to stake the token
    /// @param _user User to deposit for
    function depositAll(bool _lock, bool _stake, address _user) external {
        uint256 tokenBal = TOKEN.balanceOf(msg.sender);
        deposit(tokenBal, _lock, _stake, _user);
    }

    /// @notice Lock forever (irreversible action) old sdveCrv to sdCrv with 1:1 rate
    /// @dev User needs to approve the contract to transfer Token tokens
    /// @param _amount amount to lock
    function lockSdveCrvToSdCrv(uint256 _amount) external {
        ERC20(SD_VE_CRV).transferFrom(msg.sender, address(this), _amount);
        // mint new sdCrv to the user
        ITokenMinter(MINTER).mint(msg.sender, _amount);
    }
}
