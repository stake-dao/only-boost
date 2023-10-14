// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

// TODO: For testing, remove for production
import "forge-std/Test.sol";

import {Clone} from "solady/src/utils/Clone.sol";
import {IBooster} from "src/interfaces/IBooster.sol";
import {IConvexFactory} from "src/interfaces/IConvexFactory.sol";
import {IBaseRewardPool} from "src/interfaces/IBaseRewardPool.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract ConvexImplementation is Clone {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Denominator for percentage calculation
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Error emitted when contract is not initialized
    error FACTORY();

    /// @notice Error emitted when caller is not strategy
    error STRATEGY();

    modifier onlyStrategy() {
        if (msg.sender != strategy()) revert STRATEGY();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != address(factory())) revert FACTORY();
        _;
    }

    function initialize() external onlyFactory {
        ERC20(token()).safeApprove(address(booster()), type(uint256).max);
    }

    /// @notice Main gateway to deposit LP token into ConvexCurve
    /// @dev Only callable by the strategy
    /// @param amount Amount of LP token to deposit
    function deposit(address, uint256 amount) external onlyStrategy {
        // Deposit the amount into pid from ConvexCurve and stake it into gauge (true)
        booster().deposit(pid(), amount, true);
    }

    /// @notice Main gateway to withdraw LP token from ConvexCurve
    /// @dev Only callable by the strategy
    /// @param amount Amount of LP token to withdraw
    function withdraw(address, uint256 amount) external onlyStrategy {
        // Withdraw from Convex gauge without claiming rewards.
        baseRewardPool().withdrawAndUnwrap(amount, false);

        // Transfer the amount
        ERC20(token()).safeTransfer(msg.sender, amount);
    }

    function claim(bool _claimExtraRewards)
        external
        onlyStrategy
        returns (uint256 rewardTokenAmount, uint256 fallbackRewardTokenAmount, uint256 protocolFees)
    {
        address[] memory extraRewardTokens;
        /// We can save gas by not claiming extra rewards if we don't need them, there's no extra rewards, or not enough rewards worth to claim.
        if (_claimExtraRewards) {
            /// This will return at least 2 reward tokens, rewardToken and fallbackRewardToken.
            extraRewardTokens = getRewardTokens();
        }

        /// Claim rewardToken, fallbackRewardToken and _extraRewardTokens if _claimExtraRewards is true.
        baseRewardPool().getReward(address(this), _claimExtraRewards);

        rewardTokenAmount = ERC20(rewardToken()).balanceOf(address(this));
        fallbackRewardTokenAmount = ERC20(fallbackRewardToken()).balanceOf(address(this));

        /// Charge Fees.
        /// Amounts[0] is the amount of rewardToken claimed.
        protocolFees = _chargeProtocolFees(rewardTokenAmount);

        ERC20(rewardToken()).safeTransfer(msg.sender, rewardTokenAmount);
        ERC20(fallbackRewardToken()).safeTransfer(msg.sender, fallbackRewardTokenAmount);

        for (uint256 i = 0; i < extraRewardTokens.length;) {
            uint256 _balance = ERC20(extraRewardTokens[i]).balanceOf(address(this));
            if (_balance > 0) {
                // Transfer the reward token to the claimer.
                ERC20(extraRewardTokens[i]).safeTransfer(msg.sender, _balance);
            }

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

        address[] memory tokens = new address[](extraRewardsLength);

        address _token;
        for (uint256 i; i < extraRewardsLength;) {
            // Add the extra reward token to the array
            _token = baseRewardPool().extraRewards(i);

            /// Try Catch to see if the token is a valid ERC20
            try ERC20(_token).decimals() returns (uint8) {
                tokens[i] = _token;
            } catch {
                tokens[i] = IBaseRewardPool(_token).rewardToken();
            }

            unchecked {
                ++i;
            }
        }

        return tokens;
    }

    /// @notice Internal function to charge protocol fees from `rewardToken` claimed by the locker.
    function _chargeProtocolFees(uint256 _amount) internal view returns (uint256 _feeAccrued) {
        if (_amount == 0) return 0;

        uint256 protocolFeesPercent = factory().protocolFeesPercent();
        if (protocolFeesPercent == 0) return 0;

        _feeAccrued = _amount.mulDivDown(protocolFeesPercent, DENOMINATOR);
    }

    /// @notice Get the balance of the LP token on ConvexCurve
    /// @return Balance of the LP token on ConvexCurve
    function balanceOf(address) public view returns (uint256) {
        // Return the balance of the LP token on ConvexCurve if initialized, else 0
        return baseRewardPool().balanceOf(address(this));
    }

    //////////////////////////////////////////////////////
    /// --- IMMUTABLES
    //////////////////////////////////////////////////////

    function factory() public pure returns (IConvexFactory _factory) {
        return IConvexFactory(_getArgAddress(0));
    }

    function token() public pure returns (address _token) {
        return _getArgAddress(20);
    }

    function rewardToken() public pure returns (address _rewardToken) {
        return _getArgAddress(40);
    }

    function fallbackRewardToken() public pure returns (address _fallbackRewardToken) {
        return _getArgAddress(60);
    }

    function strategy() public pure returns (address _strategy) {
        return _getArgAddress(80);
    }

    function booster() public pure returns (IBooster _booster) {
        return IBooster(_getArgAddress(100));
    }

    function baseRewardPool() public pure returns (IBaseRewardPool _baseRewardPool) {
        return IBaseRewardPool(_getArgAddress(120));
    }

    function pid() public pure returns (uint256 _pid) {
        return _getArgUint256(140);
    }
}
