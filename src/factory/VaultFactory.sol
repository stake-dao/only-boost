// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solady/tokens/ERC20.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {IBooster} from "src/interfaces/IBooster.sol";

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IFallback} from "src/interfaces/IFallback.sol";
import {ILiquidityGaugeStrat} from "src/interfaces/ILiquidityGaugeStrat.sol";

abstract contract VaultFactory {
    using LibClone for address;

    /// @notice Denominator for fixed point math.
    uint256 public constant DENOMINATOR = 10_000;

    /// @notice Stake DAO strategy contract address.
    IStrategy public immutable strategy;

    /// @notice Staking Deposit implementation address.
    address public immutable vaultImplementation;

    /// @notice Liquidity Gauge implementation address.
    address public immutable liquidityGaugeImplementation;

    /// @notice SDT VEBoost proxy address.
    address public constant VE_BOOST_PROXY = 0xD67bdBefF01Fc492f1864E61756E5FBB3f173506;

    /// @notice Claim helper contract address for LiquidityGauges.
    address public constant CLAIM_HELPER = 0x633120100e108F03aCe79d6C78Aac9a56db1be0F;

    /// @notice Throwed if the gauge is not valid candidate.
    error INVALID_GAUGE();

    /// @notice Throwed if the token is not valid.
    error INVALID_TOKEN();

    /// @notice Throwed if the gauge has been already used.
    error GAUGE_ALREADY_USED();

    constructor(address _strategy, address _vaultImplementation, address _liquidityGaugeImplementation) {
        strategy = IStrategy(_strategy);
        vaultImplementation = _vaultImplementation;
        liquidityGaugeImplementation = _liquidityGaugeImplementation;
    }

    /// @notice Add new staking gauge to Stake DAO Locker.
    function create(address _gauge) external {
        // check if the gauge is valid
        if (!_isValidGauge(_gauge)) revert INVALID_GAUGE();
        // check if the lp has been already used to clone a vault
        if (strategy.rewardDistributors(_gauge) != address(0)) revert GAUGE_ALREADY_USED();

        address lp = _getGaugeStakingToken(_gauge);

        (string memory tokenName, string memory tokenSymbol) = _getNameAndSymbol(lp);

        /// Clone the vault.
    }

    function _addExtraRewards() internal virtual {}

    function _isValidGauge(address _gauge) internal view virtual returns (bool) {}

    function _isValidToken(address _token) internal view virtual returns (bool) {}

    function _getGaugeStakingToken(address _gauge) internal view virtual returns (address lp) {
        lp = ILiquidityGaugeStrat(_gauge).lp_token();
    }

    function _getNameAndSymbol(address _lp) internal view virtual returns (string memory name, string memory symbol) {
        name = ERC20(_lp).name();
        symbol = ERC20(_lp).symbol();
    }
}
