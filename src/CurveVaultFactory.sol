// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// --- Libraries
import {ClonesUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/ClonesUpgradeable.sol";
import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

// --- Core contracts
import {Optimizor} from "src/Optimizor.sol";
import {BaseFallback} from "src/BaseFallback.sol";
import {Strategy} from "src/Strategy.sol";

// --- Interfaces
import {ICurveVault} from "src/interfaces/ICurveVault.sol";
import {IGaugeController} from "src/interfaces/IGaugeController.sol";
import {ILiquidityGaugeStrat} from "src/interfaces/ILiquidityGaugeStrat.sol";
import {ICurveLiquidityGauge} from "src/interfaces/ICurveLiquidityGauge.sol";

/// @title Vault Factory
/// @notice Factory contract for creating new curve vaults that supports LP
/// related to the curve platform, and the liquidity gauge attached to it.
/// @author Stake DAO
contract CurveVaultFactory {
    using ClonesUpgradeable for address;

    ////////////////////////////////////////////////////////////////
    /// --- CONSTANTS
    ///////////////////////////////////////////////////////////////

    /// @notice Curve DAO token address
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    /// @notice Stake DAO token address
    address public constant SDT = 0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F;

    /// @notice Vote-escrow for SDT token address
    address public constant VESDT = 0x0C30476f66034E11782938DF8e4384970B6c9e8a;

    /// @notice Stake DAO Liquid Locker for CRV token address
    address public constant LOCKER = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;

    /// @notice Stake DAO  veboost contract address
    address public constant VEBOOST = 0xD67bdBefF01Fc492f1864E61756E5FBB3f173506;

    /// @notice Stake DAO MultiSig contract address
    address public constant GOVERNANCE = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

    /// @notice Claim rewards contract address
    address public constant CLAIM_REWARDS = 0xf30f23B7FB233172A41b32f82D263c33a0c9F8c2;

    /// @notice Curve DAO Liquidity Gauge Controller contract address
    address public constant GAUGE_CONTROLLER = 0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB;

    ////////////////////////////////////////////////////////////////
    /// --- VARIABLES
    ///////////////////////////////////////////////////////////////

    /// @notice Curve Strategy contract
    Strategy public curveStrategy;

    /// @notice Stake DAO Curve Vault implementation contract
    address public vaultImpl = 0x9FDd0A0cfD98775565811E081d404309B23ea996;

    /// @notice Stake DAO Curve Liquidity Gauge implementation contract
    address public gaugeImpl = 0x3Dc56D46F0Bd13655EfB29594a2e44534c453BF9;

    /// @notice Stake DAO SDT distributor contract address
    address public sdtDistributor = 0x9C99dffC1De1AfF7E7C1F36fCdD49063A281e18C;

    /// @notice Flag for setting all pids on fallback
    bool public setAllPids = true;

    ////////////////////////////////////////////////////////////////
    /// --- EVENTS
    ///////////////////////////////////////////////////////////////

    /// @notice Event emitted when a new vault is deployed
    /// @param proxy Address of the new deployed vault
    /// @param lpToken Address of the corresponding LP token
    /// @param impl Address of the implementation contract used as model
    event VaultDeployed(address proxy, address lpToken, address impl);

    /// @notice Event emitted when a new gauge is deployed
    /// @param proxy Address of the new deployed gauge
    /// @param stakeToken Address of the corresponding stake token
    /// @param impl Address of the implementation contract used as model
    event GaugeDeployed(address proxy, address stakeToken, address impl);

    /// @notice Event emitted when `setAllPids` flag is toggled
    /// @param status New status of the flag
    event SetAllPidsToggled(bool status);

    //////////////////////////////////////////////////////
    /// --- ERRORS
    //////////////////////////////////////////////////////

    /// @notice Error emitted when the weight of the gauge is 0
    error INVALIDE_WEIGHT();

    /// @notice Error emitted when the caller is not the governance
    error ONLY_GOVERNANCE();

    //////////////////////////////////////////////////////
    /// --- CONSTRUCTOR
    //////////////////////////////////////////////////////

    constructor(address payable _curveStrategy) {
        curveStrategy = Strategy(_curveStrategy);
    }

    //////////////////////////////////////////////////////
    /// --- MAIN FUNCTIONS FOR VAULT CREATION
    //////////////////////////////////////////////////////

    /// @notice Function to clone Curve Vault and its gauge contracts
    /// @param _crvGaugeAddress curve liqudity gauge address
    function cloneAndInit(address _crvGaugeAddress) public returns (address, address) {
        // Get the weight of the gauge
        uint256 weight = IGaugeController(GAUGE_CONTROLLER).get_gauge_weight(_crvGaugeAddress);

        // If the weight is 0, revert
        if (weight == 0) revert INVALIDE_WEIGHT();

        // Get LP token address
        address vaultLpToken = ICurveLiquidityGauge(_crvGaugeAddress).lp_token();

        // Get LP token symbol
        string memory tokenSymbol = ERC20Upgradeable(vaultLpToken).symbol();

        uint256 liquidityGaugeType;
        // view function called only to recognize the gauge type
        (bool success,) = _crvGaugeAddress.call(abi.encodeWithSignature("reward_tokens(uint256)", 0));
        if (!success) {
            liquidityGaugeType = 1; // no extra reward
        }

        // Clone and init vault
        address vaultImplAddress = _cloneAndInitVault(
            vaultImpl,
            vaultLpToken,
            GOVERNANCE,
            string(abi.encodePacked("sd", tokenSymbol, " Vault")),
            string(abi.encodePacked("sd", tokenSymbol, "-vault"))
        );

        // Clone and init gauge
        address gaugeImplAddress = _cloneAndInitGauge(gaugeImpl, vaultImplAddress, GOVERNANCE, tokenSymbol);

        // Setters
        ICurveVault(vaultImplAddress).setLiquidityGauge(gaugeImplAddress);
        ICurveVault(vaultImplAddress).setGovernance(GOVERNANCE);

        curveStrategy.toggleVault(vaultImplAddress);
        curveStrategy.setGauge(vaultLpToken, _crvGaugeAddress);
        curveStrategy.setRewardDistributor(_crvGaugeAddress, gaugeImplAddress);
        curveStrategy.manageFee(Strategy.MANAGEFEE.PERF_FEE, _crvGaugeAddress, 200); //%2 default
        curveStrategy.manageFee(Strategy.MANAGEFEE.VESDT_FEE, _crvGaugeAddress, 500); //%5 default
        curveStrategy.manageFee(Strategy.MANAGEFEE.ACCUMULATOR_FEE, _crvGaugeAddress, 800); //%8 default
        curveStrategy.manageFee(Strategy.MANAGEFEE.CLAIMER_REWARD, _crvGaugeAddress, 50); //%0.5 default
        curveStrategy.setLGtype(_crvGaugeAddress, liquidityGaugeType);

        ILiquidityGaugeStrat(gaugeImplAddress).add_reward(CRV, payable(address(curveStrategy)));
        ILiquidityGaugeStrat(gaugeImplAddress).set_claimer(CLAIM_REWARDS);
        ILiquidityGaugeStrat(gaugeImplAddress).commit_transfer_ownership(GOVERNANCE);

        // Update pids mapping on fallbacks
        _updatePidsOnFallbacks();

        return (vaultImplAddress, gaugeImplAddress);
    }

    /// @notice Toggle setAllPids variable
    /// @dev Only callable by `governance`
    function toggleSetAllPids() public {
        // Only governance can call this function
        if (msg.sender != GOVERNANCE) revert ONLY_GOVERNANCE();

        // Toggle setAllPids
        setAllPids = !setAllPids;

        // Emit event
        emit SetAllPidsToggled(setAllPids);
    }

    //////////////////////////////////////////////////////
    /// --- INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Internal function to clone the vault
    /// @param _impl address of contract to clone
    /// @param _lpToken curve LP token address
    /// @param _governance governance address
    /// @param _name vault name
    /// @param _symbol vault symbol
    /// @return deployed vault address
    function _cloneAndInitVault(
        address _impl,
        address _lpToken,
        address _governance,
        string memory _name,
        string memory _symbol
    ) internal returns (address) {
        // Clone and Deploy Vault
        address deployed =
            cloneVault(_impl, _lpToken, keccak256(abi.encodePacked(_governance, _name, _symbol, curveStrategy)));

        // Init Vault
        ICurveVault(deployed).init(_lpToken, address(this), _name, _symbol, payable(address(curveStrategy)));

        // Return vault address
        return address(deployed);
    }

    /// @notice Internal function to clone the gauge multi rewards
    /// @param _impl address of contract to clone
    /// @param _stakingToken sd LP token address
    /// @param _governance governance address
    /// @param _symbol gauge symbol
    /// @return deployed gauge address
    function _cloneAndInitGauge(address _impl, address _stakingToken, address _governance, string memory _symbol)
        internal
        returns (address)
    {
        // Clone and Deploy Gauge
        ILiquidityGaugeStrat deployed =
            cloneGauge(_impl, _stakingToken, keccak256(abi.encodePacked(_governance, _symbol)));

        // Init Gauge
        deployed.initialize(_stakingToken, address(this), SDT, VESDT, VEBOOST, sdtDistributor, _stakingToken, _symbol);

        // Return gauge address
        return address(deployed);
    }

    /// @notice Internal function that deploy and returns a clone of vault impl
    /// @param _impl address of contract to clone
    /// @param _lpToken curve LP token address
    /// @param _paramsHash governance+name+symbol+strategy parameters hash
    /// @return deployed vault address
    function cloneVault(address _impl, address _lpToken, bytes32 _paramsHash) internal returns (address) {
        // Clone and Deploy Vault
        address deployed =
            address(_impl).cloneDeterministic(keccak256(abi.encodePacked(address(_lpToken), _paramsHash)));

        // Emit event
        emit VaultDeployed(deployed, address(_lpToken), _impl);

        // Return vault address
        return deployed;
    }

    /// @notice Internal function that deploy and returns a clone of gauge impl
    /// @param _impl address of contract to clone
    /// @param _stakingToken sd LP token address
    /// @param _paramsHash governance+name+symbol parameters hash
    /// @return deployed gauge address
    function cloneGauge(address _impl, address _stakingToken, bytes32 _paramsHash)
        internal
        returns (ILiquidityGaugeStrat)
    {
        // Clone and Deploy Gauge
        address deployed =
            address(_impl).cloneDeterministic(keccak256(abi.encodePacked(address(_stakingToken), _paramsHash)));

        // Emit event
        emit GaugeDeployed(deployed, _stakingToken, _impl);

        // Return gauge address
        return ILiquidityGaugeStrat(deployed);
    }

    /// @notice Internal function to update pids on fallbacks
    function _updatePidsOnFallbacks() internal {
        // Only update pids on fallbacks if setAllPids boolean is true
        if (setAllPids) {
            // Get optimizor address
            Optimizor optimizor = curveStrategy.optimizor();

            // If optimizor is set, update pids on fallbacks
            if (address(optimizor) != address(0)) {
                // Get fallbacks
                address[] memory fallbacks = optimizor.getFallbacks();

                // Loop through fallbacks and update pids
                for (uint8 i = 0; i < fallbacks.length; ++i) {
                    // Skip locker
                    if (fallbacks[i] == LOCKER) continue;

                    // Set all pids optimized
                    BaseFallback(fallbacks[i]).setAllPidsOptimized();
                }
            }
        }
    }

    //////////////////////////////////////////////////////
    /// --- VIEW FUNCTIONS
    //////////////////////////////////////////////////////

    /// @notice Function that predicts the future address passing the parameters
    /// @param _impl address of contract to clone
    /// @param _token token (LP or sdLP)
    /// @param _paramsHash parameters hash
    /// @return future address
    function predictAddress(address _impl, address _token, bytes32 _paramsHash) public view returns (address) {
        return address(_impl).predictDeterministicAddress(keccak256(abi.encodePacked(_token, _paramsHash)));
    }
}
