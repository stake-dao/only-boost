// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/src/Test.sol";

import "solady/src/utils/LibClone.sol";
import "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";

import "src/shutdown/v2/CurveShutdownStrategy.sol";
import "src/interfaces/IVault.sol";

import {SafeTransferLib as SafeTransfer} from "solady/src/utils/SafeTransferLib.sol";

contract ShutdownTest is Test {
    using SafeTransfer for ERC20;
    using FixedPointMathLib for uint256;

    CurveShutdownStrategy public strategy;

    /// @notice Event for testing
    event ShutdownModeChanged(CurveShutdownStrategy.ShutdownMode newMode);

    /// @notice The ERC1967 implementation slot.
    bytes32 internal constant _ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Current strategy address.
    address public constant STRATEGY = 0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd;

    /// We have two versions of the vault, V1 and V2.
    // We need to make sure the shutdown strategy works for both.
    /// @notice Vault V1 address.
    /// @dev Vault V1 version
    address public constant VAULT_V1 = address(0x98dd95D0ac5b70B0F4ae5080a1C2EeA8c5c48387);

    /// @notice Vault V2 address.
    /// @dev Vault V2 version
    address public constant VAULT_V2 = address(0x2eB6af2F70fc14E324A5E326296708e7E9EbDfAb);

    address public governance;

    function setUp() public virtual {
        vm.createSelectFork("mainnet", 22_117_697);

        governance = CurveShutdownStrategy(payable(STRATEGY)).governance();

        address locker = address(CurveShutdownStrategy(payable(STRATEGY)).locker());
        address veToken = CurveShutdownStrategy(payable(STRATEGY)).veToken();
        address rewardToken = CurveShutdownStrategy(payable(STRATEGY)).rewardToken();
        address minter = CurveShutdownStrategy(payable(STRATEGY)).minter();

        /// 1. Deploy the strategy implementation.
        strategy = new CurveShutdownStrategy(governance, locker, veToken, rewardToken, minter);
    }

    function test_upgrade() public {
        /// 1. Expect the upgrade to revert.
        vm.expectRevert(Strategy.GOVERNANCE.selector);
        CurveShutdownStrategy(payable(STRATEGY)).upgradeToAndCall(address(strategy), "");

        /// 2. Expect the upgrade to revert for the new implementation.
        vm.expectRevert(UUPSUpgradeable.UnauthorizedCallContext.selector);
        strategy.upgradeToAndCall(address(1), "");

        /// 3. Upgrade the strategy.
        _upgrade(address(strategy));

        /// 4. Expect the upgrade to succeed.
        bytes32 v = vm.load(address(STRATEGY), _ERC1967_IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(v))), address(strategy));
    }

    function test_shutdown() public {
        /// Upgrade the strategy.
        _upgrade(address(strategy));

        /// Verify default mode after upgrade (storage starts at 0 = NORMAL)
        assertEq(
            uint256(CurveShutdownStrategy(payable(STRATEGY)).shutdownMode()),
            uint256(CurveShutdownStrategy.ShutdownMode.NORMAL)
        );

        /// Set to AUTO_SHUTDOWN mode to maintain current behavior
        vm.prank(governance);
        CurveShutdownStrategy(payable(STRATEGY)).setShutdownMode(CurveShutdownStrategy.ShutdownMode.AUTO_SHUTDOWN);

        /// V1 vault token.
        _shutdown(VAULT_V1);

        /// V2 vault token.
        _shutdown(VAULT_V2);
    }

    function _shutdown(address _vault) internal {
        /// V1 vault token.
        address asset = IVault(_vault).token();
        address liquidityGauge = IVault(_vault).liquidityGauge();
        address gauge = CurveShutdownStrategy(payable(STRATEGY)).gauges(asset);

        /// Deposit some assets.
        deal(asset, address(this), 1000e18);
        SafeTransfer.safeApprove(asset, _vault, type(uint256).max);
        IVault(_vault).deposit(address(this), 1000e18, true);

        assertEq(_balanceOf(asset, STRATEGY), 0);
        assertEq(_balanceOf(asset, _vault), 0);
        assertEq(_balanceOf(liquidityGauge, address(this)), 1000e18);

        uint256 balance = CurveShutdownStrategy(payable(STRATEGY)).balanceOf(asset);
        assertGt(balance, 1000e18);

        assertEq(CurveShutdownStrategy(payable(STRATEGY)).isShutdown(gauge), false);

        address[] memory protectedGauges = new address[](1);
        protectedGauges[0] = gauge;

        vm.prank(governance);
        CurveShutdownStrategy(payable(STRATEGY)).setProtectedGauges(protectedGauges);

        CurveShutdownStrategy(payable(STRATEGY)).harvest(asset, false, false, false);

        assertEq(CurveShutdownStrategy(payable(STRATEGY)).isShutdown(gauge), false);
        assertEq(_balanceOf(asset, _vault), 0);

        skip(1 days);

        vm.prank(governance);
        CurveShutdownStrategy(payable(STRATEGY)).unsetProtectedGauges(protectedGauges);

        CurveShutdownStrategy(payable(STRATEGY)).harvest(asset, false, false, false);

        assertEq(CurveShutdownStrategy(payable(STRATEGY)).isShutdown(gauge), true);

        assertEq(_balanceOf(asset, STRATEGY), 0);
        assertEq(_balanceOf(asset, _vault), balance);

        /// Make sure you can't harvest again.
        vm.expectRevert(CurveShutdownStrategy.SHUTDOWN.selector);
        CurveShutdownStrategy(payable(STRATEGY)).harvest(asset, false, false, false);

        /// Make sure you can't call regular harvest.
        vm.expectRevert(CurveShutdownStrategy.SHUTDOWN.selector);
        CurveShutdownStrategy(payable(STRATEGY)).harvest(asset, false, false);

        /// Make sure the strategy is not rebalanceable.
        vm.expectRevert(CurveShutdownStrategy.SHUTDOWN.selector);
        CurveShutdownStrategy(payable(STRATEGY)).rebalance(asset);

        /// Make sure you can withdraw.
        IVault(_vault).withdraw(1000e18);

        assertEq(_balanceOf(asset, address(this)), 1000e18);
        assertEq(_balanceOf(liquidityGauge, address(this)), 0);

        /// Make sure you can't deposit again.
        vm.expectRevert(CurveShutdownStrategy.SHUTDOWN.selector);
        IVault(_vault).deposit(address(this), 1000e18, true);
    }

    function _balanceOf(address _token, address account) internal view returns (uint256) {
        if (_token == address(0)) {
            return account.balance;
        }

        return ERC20(_token).balanceOf(account);
    }

    function test_shutdownModeNormal() public {
        /// Upgrade the strategy.
        _upgrade(address(strategy));

        /// Set to NORMAL mode
        vm.prank(governance);
        CurveShutdownStrategy(payable(STRATEGY)).setShutdownMode(CurveShutdownStrategy.ShutdownMode.NORMAL);

        /// Test with V1 vault
        _testNormalMode(VAULT_V1);
    }

    function test_shutdownModeSelective() public {
        /// Upgrade the strategy.
        _upgrade(address(strategy));

        /// Set to SELECTIVE_SHUTDOWN mode
        vm.prank(governance);
        CurveShutdownStrategy(payable(STRATEGY)).setShutdownMode(CurveShutdownStrategy.ShutdownMode.SELECTIVE_SHUTDOWN);

        /// Test with V1 vault
        _testSelectiveMode(VAULT_V1);
    }

    function test_shutdownModeChange() public {
        /// Upgrade the strategy.
        _upgrade(address(strategy));

        /// Test that non-governance cannot change mode
        vm.expectRevert(Strategy.GOVERNANCE.selector);
        CurveShutdownStrategy(payable(STRATEGY)).setShutdownMode(CurveShutdownStrategy.ShutdownMode.NORMAL);

        /// Test governance can change mode and event is emitted
        vm.expectEmit(true, true, true, true);
        emit ShutdownModeChanged(CurveShutdownStrategy.ShutdownMode.NORMAL);

        vm.prank(governance);
        CurveShutdownStrategy(payable(STRATEGY)).setShutdownMode(CurveShutdownStrategy.ShutdownMode.NORMAL);

        /// Verify mode changed
        assertEq(
            uint256(CurveShutdownStrategy(payable(STRATEGY)).shutdownMode()),
            uint256(CurveShutdownStrategy.ShutdownMode.NORMAL)
        );
    }

    function _testNormalMode(address _vault) internal {
        address asset = IVault(_vault).token();
        address gauge = CurveShutdownStrategy(payable(STRATEGY)).gauges(asset);

        /// Deposit some assets
        deal(asset, address(this), 1000e18);
        SafeTransfer.safeApprove(asset, _vault, type(uint256).max);
        IVault(_vault).deposit(address(this), 1000e18, true);

        uint256 balance = CurveShutdownStrategy(payable(STRATEGY)).balanceOf(asset);
        assertGt(balance, 1000e18);

        /// Harvest multiple times - should never shutdown in NORMAL mode
        CurveShutdownStrategy(payable(STRATEGY)).harvest(asset, false, false, false);
        assertEq(CurveShutdownStrategy(payable(STRATEGY)).isShutdown(gauge), false);

        skip(1 days);
        CurveShutdownStrategy(payable(STRATEGY)).harvest(asset, false, false, false);
        assertEq(CurveShutdownStrategy(payable(STRATEGY)).isShutdown(gauge), false);

        /// Verify funds are still in strategy
        assertEq(_balanceOf(asset, _vault), 0);
        assertGt(CurveShutdownStrategy(payable(STRATEGY)).balanceOf(asset), 0);

        /// Cleanup
        IVault(_vault).withdraw(1000e18);
    }

    function _testSelectiveMode(address _vault) internal {
        address asset = IVault(_vault).token();
        address gauge = CurveShutdownStrategy(payable(STRATEGY)).gauges(asset);
        address randomUser = address(0x123);

        /// Deposit some assets
        deal(asset, address(this), 1000e18);
        SafeTransfer.safeApprove(asset, _vault, type(uint256).max);
        IVault(_vault).deposit(address(this), 1000e18, true);

        uint256 balance = CurveShutdownStrategy(payable(STRATEGY)).balanceOf(asset);
        assertGt(balance, 1000e18);

        /// Test 1: Non-owner harvest should NOT shutdown
        vm.prank(randomUser);
        CurveShutdownStrategy(payable(STRATEGY)).harvest(asset, false, false, false);
        assertEq(CurveShutdownStrategy(payable(STRATEGY)).isShutdown(gauge), false);

        skip(1 days);

        /// Test 2: Owner harvest SHOULD shutdown
        vm.prank(governance);
        CurveShutdownStrategy(payable(STRATEGY)).harvest(asset, false, false, false);
        assertEq(CurveShutdownStrategy(payable(STRATEGY)).isShutdown(gauge), true);

        /// Verify funds returned to vault
        assertEq(_balanceOf(asset, STRATEGY), 0);
        assertEq(_balanceOf(asset, _vault), balance);

        /// Cleanup
        IVault(_vault).withdraw(1000e18);
    }

    function _upgrade(address _newImplementation) internal {
        vm.prank(governance);
        CurveShutdownStrategy(payable(STRATEGY)).upgradeToAndCall(address(_newImplementation), "");
    }
}
