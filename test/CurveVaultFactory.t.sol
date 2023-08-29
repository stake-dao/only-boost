// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.20;

import "test/BaseTest.t.sol";

contract CurveVaultFactoryTest is BaseTest {
    address public constant VAULT_IMPL = 0x9FDd0A0cfD98775565811E081d404309B23ea996;
    address public constant GAUGE_IMPL = 0x3Dc56D46F0Bd13655EfB29594a2e44534c453BF9;

    function setUp() public {
        _labelAddress();

        // --- Fork --- //
        vm.rollFork(17634100);

        // --- Deploy Contracts --- //
        vm.startPrank(MS_STAKEDAO);

        // Roles
        rolesAuthority = new RolesAuthority(MS_STAKEDAO, Authority(address(0)));

        // Curve Strategy
        curveStrategy = new CurveStrategy(MS_STAKEDAO, rolesAuthority);

        // Curve Vault Factory
        curveVaultFactory = new CurveVaultFactory(payable(address(curveStrategy)));

        // Fallbacks
        fallbackConvexCurve = new ConvexFallback(MS_STAKEDAO, rolesAuthority, payable(address(curveStrategy))); // Convex Curve

        // Optimizor
        optimizor =
            new Optimizor(MS_STAKEDAO, rolesAuthority, payable(address(curveStrategy)), address(fallbackConvexCurve));

        vm.stopPrank();

        // --- Setters --- //
        // Set Optimizor on Curve Strategy
        vm.prank(MS_STAKEDAO);
        curveStrategy.setOptimizor(address(optimizor));

        // 1. Create roles for `toggleVault` on Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(1, payable(address(curveStrategy)), CurveStrategy.toggleVault.selector, true);

        // 1. Grant `toggleVault` role from Curve Strategy to Vault Factory
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(curveVaultFactory), 1, true);

        // 2. Create roles for `setGauge` on Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(2, payable(address(curveStrategy)), CurveStrategy.setGauge.selector, true);

        // 2. Grant `setGauge` role from Curve Strategy to Vault Factory
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(curveVaultFactory), 2, true);

        // 3. Create roles for `manageFee` on Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(3, payable(address(curveStrategy)), CurveStrategy.manageFee.selector, true);

        // 3. Grant `manageFee` role from Curve Strategy to Vault Factory
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(curveVaultFactory), 3, true);

        // 4. Create roles for `setMultiGauge` on Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(4, payable(address(curveStrategy)), CurveStrategy.setMultiGauge.selector, true);

        // 4. Grant `setMultiGauge` role from Curve Strategy to Vault Factory
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(curveVaultFactory), 4, true);

        // 5. Create roles for `setLGtype` on Curve Strategy
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(5, payable(address(curveStrategy)), CurveStrategy.setLGtype.selector, true);

        // 5. Grant `setLGtype` role from Curve Strategy to Vault Factory
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(curveVaultFactory), 5, true);

        // 6. Create roles for `setAllPidsOptimized` on Curve Fallback
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setRoleCapability(
            6, address(fallbackConvexCurve), BaseFallback.setAllPidsOptimized.selector, true
        );

        // 6. Grant `setAllPidsOptimized` role from Fallback to Vault Factory
        vm.prank(MS_STAKEDAO);
        rolesAuthority.setUserRole(address(curveVaultFactory), 6, true);

        // Give strategy roles from depositor to new strategy
        locker = ILocker(LOCKER);

        vm.prank(locker.governance());
        locker.setStrategy(payable(address(curveStrategy)));

        _labelContract();
    }

    function test_CloneVaultAndGauge_SWETH_FXETH() public {
        _test_VaultAndGaugeCreation(GAUGE_SWETH_FXETH);
    }

    function test_ToggleSetAllPids() public {
        bool before = curveVaultFactory.setAllPids();

        vm.prank(MS_STAKEDAO);
        curveVaultFactory.toggleSetAllPids();

        assertEq(curveVaultFactory.setAllPids(), !before);
    }

    function _test_VaultAndGaugeCreation(address _curveGauge) internal {
        // Clone and init vault and gauge
        (address vault, address gauge) = curveVaultFactory.cloneAndInit(_curveGauge);
        _labelVaultAndGauge(vault, gauge);

        // Get LP token address
        address vaultLpToken = ICurveLiquidityGauge(_curveGauge).lp_token();

        // Get LP token symbol
        string memory tokenSymbol = ERC20(vaultLpToken).symbol();

        string memory vaultName = string(abi.encodePacked("sd", tokenSymbol, " Vault"));
        string memory vaultSymbol = string(abi.encodePacked("sd", tokenSymbol, "-vault"));

        // --- Assertions --- //
        assertEq(ERC20(vault).name(), vaultName);
        assertEq(ERC20(vault).symbol(), vaultSymbol);

        assertEq(ERC20(gauge).name(), string(abi.encodePacked("Stake DAO ", tokenSymbol, " Gauge")));
        assertEq(ERC20(gauge).symbol(), string(abi.encodePacked("sd", tokenSymbol, "-gauge")));
    }

    ////////////////////////////////////////////////////////////////
    /// --- HELPERS
    ///////////////////////////////////////////////////////////////

    function _labelVaultAndGauge(address vault, address gauge) internal {
        vm.label(vault, ICurveVault(vault).name());
        vm.label(gauge, ILiquidityGaugeStrat(gauge).name());
    }
}
