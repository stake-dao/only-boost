// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "src/CRVStrategy.sol";
import "solady/utils/LibClone.sol";

contract UUPSUpgradeableTest is Test {
    using FixedPointMathLib for uint256;

    CRVStrategy proxy;
    CRVStrategy implementation;

    bytes32 internal constant _ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    //////////////////////////////////////////////////////
    /// --- CONVEX ADDRESSES
    //////////////////////////////////////////////////////

    address public constant BOOSTER = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant REWARD_TOKEN = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant FALLBACK_REWARD_TOKEN = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    //////////////////////////////////////////////////////
    /// --- VOTER PROXY ADDRESSES
    //////////////////////////////////////////////////////

    address public constant SD_VOTER_PROXY = 0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6;
    address public constant CONVEX_VOTER_PROXY = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    //////////////////////////////////////////////////////
    /// --- CURVE ADDRESSES
    //////////////////////////////////////////////////////

    address public constant VE_CRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address public constant MINTER = 0xd061D61a4d941c39E5453435B6345Dc261C2fcE0;

    function setUp() public {
        implementation = new CRVStrategy(address(this), SD_VOTER_PROXY, VE_CRV, REWARD_TOKEN, MINTER);

        address _proxy = LibClone.deployERC1967(address(implementation));
        proxy = CRVStrategy(payable(_proxy));

        proxy.initialize(address(this));
    }

    event Upgraded(address indexed implementation);

    function test_InitialValues() public {
        /// Proxy values
        assertEq(proxy.veToken(), VE_CRV);
        assertEq(proxy.rewardToken(), REWARD_TOKEN);
        assertEq(proxy.minter(), MINTER);
        assertEq(address(proxy.locker()), SD_VOTER_PROXY);
        assertEq(proxy.governance(), address(this));

        /// Impl values
        assertEq(implementation.veToken(), VE_CRV);
        assertEq(implementation.rewardToken(), REWARD_TOKEN);
        assertEq(implementation.minter(), MINTER);
        assertEq(address(implementation.locker()), SD_VOTER_PROXY);
        assertEq(implementation.governance(), address(this));
    }

    function test_initializeTwice() public {
        vm.expectRevert(Strategy.GOVERNANCE.selector);
        proxy.initialize(address(0xCAFE));

        vm.expectRevert(Strategy.GOVERNANCE.selector);
        implementation.initialize(address(0xCAFE));
    }

    function test_NotDelegatedGuard() public {
        assertEq(implementation.proxiableUUID(), _ERC1967_IMPLEMENTATION_SLOT);

        vm.expectRevert(UUPSUpgradeable.UnauthorizedCallContext.selector);
        proxy.proxiableUUID();
    }

    function test_OnlyProxyGuard() public {
        vm.expectRevert(UUPSUpgradeable.UnauthorizedCallContext.selector);
        implementation.upgradeTo(address(1));
    }

    function test_UpgradeToWrongCaller() public {
        vm.prank(address(0xCAFE));
        vm.expectRevert(Strategy.GOVERNANCE.selector);
        proxy.upgradeTo(address(1));
    }

    function test_updateGovernanceAndUpdate() public {
        CRVStrategy impl2 = new CRVStrategy(address(this), SD_VOTER_PROXY, VE_CRV, REWARD_TOKEN, MINTER);

        proxy.transferGovernance(address(0xCAFE));

        vm.prank(address(0xCAFE));
        proxy.acceptGovernance();

        assertEq(proxy.governance(), address(0xCAFE));

        vm.expectRevert(Strategy.GOVERNANCE.selector);
        proxy.upgradeTo(address(impl2));

        vm.prank(address(0xCAFE));
        proxy.upgradeTo(address(impl2));

        bytes32 v = vm.load(address(proxy), _ERC1967_IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(v))), address(impl2));
    }

    function test_UpgradeTo() public {
        CRVStrategy impl2 = new CRVStrategy(address(this), SD_VOTER_PROXY, VE_CRV, REWARD_TOKEN, MINTER);

        vm.expectEmit(true, true, true, true);

        emit Upgraded(address(impl2));
        proxy.upgradeTo(address(impl2));

        bytes32 v = vm.load(address(proxy), _ERC1967_IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(v))), address(impl2));
    }
}
