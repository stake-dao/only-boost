// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {Clone} from "solady/src/utils/Clone.sol";
import {IBooster} from "src/interfaces/IBooster.sol";
import {IBaseRewardPool} from "src/interfaces/IBaseRewardPool.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract ConvexImplementation is Clone {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Denominator for percentage calculation
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Percentage of rewards to be charged as protocol fees
    uint256 public protocolFeesPercent;

    function initialize() external {
        ERC20(token()).safeApprove(address(booster()), type(uint256).max);
    }

    //////////////////////////////////////////////////////
    /// --- EVENTS & ERRORS
    //////////////////////////////////////////////////////

    /// @notice Emitted when a token is deposited
    /// @param amount Amount of token deposited
    event Deposited(uint256 amount);

    /// @notice Emitted when a token is withdrawn
    /// @param amount Amount of token withdrawn
    event Withdrawn(uint256 amount);

    /// @notice Error emitted when caller is not strategy
    error STRATEGY();

    modifier onlyStrategy() {
        if (msg.sender != strategy()) revert STRATEGY();
        _;
    }

    /// @notice Main gateway to deposit LP token into ConvexCurve
    /// @dev Only callable by the strategy
    /// @param amount Amount of LP token to deposit
    function deposit(uint256 amount) external onlyStrategy {
        // Deposit the amount into pid from ConvexCurve and stake it into gauge (true)
        booster().deposit(pid(), amount, true);

        emit Deposited(amount);
    }

    /// @notice Main gateway to withdraw LP token from ConvexCurve
    /// @dev Only callable by the strategy
    /// @param amount Amount of LP token to withdraw
    function withdraw(uint256 amount) external onlyStrategy {
        // Withdraw from Convex gauge without claiming rewards.
        baseRewardPool().withdrawAndUnwrap(amount, false);

        // Transfer the amount
        ERC20(token()).safeTransfer(msg.sender, amount);

        emit Withdrawn(amount);
    }

    /// @notice Main gateway to claim rewards from ConvexCurve
    /// @dev Only callable by the strategy
    /// @return rewardTokens Array of rewards tokens address
    /// @return amounts Array of rewards tokens amount
    function claim(bool _claimExtraRewards)
        external
        onlyStrategy
        returns (address[] memory rewardTokens, uint256[] memory amounts, uint256 _protocolFees)
    {
        /// We can save gas by not claiming extra rewards if we don't need them, there's no extra rewards, or not enough rewards worth to claim.
        if (_claimExtraRewards) {
            /// This will return at least 2 reward tokens, rewardToken and fallbackRewardToken.
            rewardTokens = getRewardTokens();
        } else {
            rewardTokens = new address[](2);
            rewardTokens[0] = rewardToken();
            rewardTokens[1] = fallbackRewardToken();
        }

        amounts = new uint256[](rewardTokens.length);

        /// Claim rewardToken, fallbackRewardToken and _extraRewardTokens if _claimExtraRewards is true.
        baseRewardPool().getReward(address(this), _claimExtraRewards);

        /// Charge Fees.
        /// Amounts[0] is the amount of rewardToken claimed.
        (amounts[0], _protocolFees) = _chargeProtocolFees(ERC20(rewardTokens[0]).balanceOf(address(this)));

        /// Transfer the reward token to the claimer.
        ERC20(rewardTokens[0]).safeTransfer(msg.sender, amounts[0]);

        for (uint256 i = 1; i < rewardTokens.length;) {
            // Get the balance of the reward token.
            amounts[i] = ERC20(rewardTokens[i]).balanceOf(address(this));

            // Transfer the reward token to the claimer.
            ERC20(rewardTokens[i]).safeTransfer(msg.sender, amounts[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get all the rewards tokens from pid corresponding to `token`
    /// @return Array of rewards tokens address
    function getRewardTokens() public view returns (address[] memory) {
        // Check if there is extra rewards
        uint256 extraRewardsLength = baseRewardPool().extraRewardsLength();

        address[] memory tokens = new address[](extraRewardsLength + 2);
        tokens[0] = rewardToken();
        tokens[1] = fallbackRewardToken();

        address _token;
        for (uint256 i; i < extraRewardsLength;) {
            // Add the extra reward token to the array
            _token = baseRewardPool().extraRewards(i);

            /// Try Catch to see if the token is a valid ERC20
            try ERC20(_token).decimals() returns (uint8) {
                tokens[i + 2] = _token;
            } catch {
                tokens[i + 2] = IBaseRewardPool(_token).rewardToken();
            }

            unchecked {
                ++i;
            }
        }

        return tokens;
    }

    function updateProtocolFeesPercent(uint256 _protocolFeesPercent) external onlyStrategy {
        protocolFeesPercent = _protocolFeesPercent;
    }

    /// @notice Internal function to charge protocol fees from `rewardToken` claimed by the locker.
    function _chargeProtocolFees(uint256 _amount) internal view returns (uint256, uint256) {
        if (_amount == 0) return (0, 0);
        if (protocolFeesPercent == 0) return (_amount, 0);

        uint256 _feeAccrued = _amount.mulDivDown(protocolFeesPercent, DENOMINATOR);

        return (_amount - _feeAccrued, _feeAccrued);
    }

    /// @notice Get the balance of the LP token on ConvexCurve
    /// @return Balance of the LP token on ConvexCurve
    function balanceOf() public view returns (uint256) {
        // Return the balance of the LP token on ConvexCurve if initialized, else 0
        return baseRewardPool().balanceOf(address(this));
    }

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    function token() public pure returns (address _token) {
        return _getArgAddress(0);
    }

    function rewardToken() public pure returns (address _rewardToken) {
        return _getArgAddress(20);
    }

    function fallbackRewardToken() public pure returns (address _fallbackRewardToken) {
        return _getArgAddress(40);
    }

    function strategy() public pure returns (address _strategy) {
        return _getArgAddress(60);
    }

    function booster() public pure returns (IBooster _booster) {
        return IBooster(_getArgAddress(80));
    }

    function baseRewardPool() public pure returns (IBaseRewardPool _baseRewardPool) {
        return IBaseRewardPool(_getArgAddress(100));
    }

    function pid() public pure returns (uint256 _pid) {
        return _getArgUint256(120);
    }
}
