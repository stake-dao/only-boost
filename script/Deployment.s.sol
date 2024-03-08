// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "src/CRVStrategy.sol";
import "solady/utils/LibClone.sol";

import "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IVault} from "script/utils/IVault.sol";
import {ILocker} from "src/interfaces/ILocker.sol";
import {IBooster} from "src/interfaces/IBooster.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {ISDLiquidityGauge} from "src/interfaces/ISDLiquidityGauge.sol";
import {SafeTransferLib as SafeTransfer} from "solady/utils/SafeTransferLib.sol";

import {ICVXLocker, Optimizer} from "src/optimizer/Optimizer.sol";
import {IBaseRewardPool, ConvexImplementation} from "src/fallbacks/ConvexImplementation.sol";
import {IBooster, ConvexMinimalProxyFactory} from "src/fallbacks/ConvexMinimalProxyFactory.sol";

interface IOldStrategy is IStrategy {
    function multiGauges(address) external view returns (address);
}

contract Deployment is Script, Test {
    using FixedPointMathLib for uint256;

    address public constant DEPLOYER = 0x000755Fbe4A24d7478bfcFC1E561AfCE82d1ff62;
    address public constant GOVERNANCE = 0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063;

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

    ILocker locker = ILocker(SD_VOTER_PROXY);

    CRVStrategy public strategy;
    CRVStrategy public stratImplementation;

    Optimizer public optimizer;
    ConvexMinimalProxyFactory public factory;

    /// @notice Implementation contract to clone.
    ConvexImplementation public implementation;

    /// @notice Convex Depositor.
    ConvexImplementation public proxy;

    // Reward distributors array
    // Reward distributors array
    address[] public rewardDistributors = [
        0xf99FD99711671268EE557fEd651EA45e34B2414f,
        0xA7Ae691A17CA71Ca24b2D21De117213c2b64A54b,
        0x087143dDEc7e00028AA0e446f486eAB8071b1f53,
        0xfA51194E8eafc40523574A65C1e4606E1432408B,
        0x3794C7C69B9c761ede266A9e8B8bb0f6cdf4E3E5,
        0x0bDabcDc2d2d41789A8F225F66ADbdc0CbDF6641,
        0x4D69ad5F243571AA9628bd88ebfFA2C913427b0b,
        0x28766020a5A8D3325863Bf533459130DDb0c3657,
        0xba621b27F071E249713866d7D7D0A97B12D2fa9b,
        0xEf965bD7539B8B9AD16e3930c97113710b7ec369,
        0x24520cdD0A0Cd242e78C6C5133A4a6a235d5A783,
        0x4a1C13D3887AE6e7289c4e0Cd7Ed1a4d1A3e21AE,
        0xCE85de920110af9101f77620E901743c16b58FDd,
        0x9B85d6e87350c021616Ae3DA78b9B1335c68283A,
        0xc0F082C886b94f36F67C6659bE01C0069968Cd0E,
        0xaC7606876CeC9C02dC2dFe057F4024165D7cd86F,
        0x78f4f7025D5DD8ad754f21b23Ee1C0B77c371767,
        0x5056c3f17e45bdF11e09b1EF82a949dD68159C0E,
        0xC891a1BaCF802127874054e703b386346fE94b00,
        0xA89B9c336764c9Ae5f64Bc19688601341974bc22,
        0x8527b2201Df6bfd09855AE5b28475DcC4A33C4f8,
        0xb10DE77F94AFd8080FB7b563ee0d6388291F07Fb,
        0x1E3923A498de30ff8C5Ac8bfAb1De9AFa58fDE5d,
        0x531167aBE95375Ec212f2b5417EF05a9953410C1,
        0x8fAC850769B6bbeEe28ae9B987C19e04999aA439,
        0xBe77585F4159e674767Acf91284160E8C09b96D8,
        0xc9CB5e84ADFa9F32Ed183e15ef423Bce93B845a9,
        0x6Fb81473F546457a96E1A5475a1f0A1717C18873,
        0x1B31C86024145583Ff37024A6B9aa8581A5070De,
        0x8672E5C9E724E593afF47549E3D47EEB9B750aB3,
        0x8474ed9bAe897B476aA98b7f1595a93e5E4A99cD,
        0x1aA62A793423d49496078F6814320706d91094AC,
        0x54aA01Ed2a0533CD9E58799C0b32AC7e1554C4cf,
        0x63f222079608EEc2DDC7a9acdCD9344a21428Ce7,
        0xcBA53d97121Cc23E1506507a444cB42066bc0dC2,
        0xDE1F1698cD6228892fEAD129b733100367564c40,
        0x131Dc928F9Dad07F43CEfF269e1674b7eBbFcBB1,
        0x4b95F9f85857341cC2876c15C88091a04eE5Cb31,
        0xB3a33E69582623F650e54Cc1cf4e439473A28D26,
        0x31539d93f3504571A5ec85510ae15289A3b299De,
        0xE0d086E44bd5BB88d3F381440D5345C1f2dcDaCa,
        0x05717c25BF7FA97b1feceb028A3e99Bd89bddDF8,
        0xdc43073cF00E616e9F80B95991Fa7732a397E6Ae,
        0x768d4Cf3439494b36bD3a8e9beCE6B1C12e599c8,
        0xD3aF4A839e09Ad759b9ccF02Fa2dDA3197ebe7d3,
        0xc0A63f4f3033a1f09804624f9666Fd214925FD06,
        0xA7f6547EA82589D0d5E789BdFCc412E296D21582,
        0x62C6f1f58c0cc5915c9d414a470F06E137c3DbdB,
        0x83EB53801dDaC98eCaaA6Ee5Ed859F08b1f4D905,
        0xDfFBb620BA3DaBa85536105E16a13cd989A705cF,
        0x0E4d110Ff0a43d895081B02A3E9Ec426Ff79118C,
        0x6655C64A607F6fc4CE4D94A40657f364436F9dF4,
        0xB41639Fc6c2A4e55b5eA8706EafAA404bCE8C4f7,
        0x6E65845aE23Df033446Ee61d1A3772DbFA0Fd15F,
        0x4875D5E7987C93431E6DB9DC53A136F46270F0Dc,
        0x1f1a798cBDf4E9d533CEB9386e0A19b8C3F99121,
        0xB5eFFc36c1231f6fBd54F4b37047a7382B66DD30,
        0xA9812ED1077938E88577be7A8eaf097b5337fF5b,
        0x2A2E11aA2B7988Ae4B5D21048699e4a4905bFCBA,
        0x2C4D6ABc7F76f9bB77CDF4D729d754020dd8DDDD,
        0xC207647B344455272E1278120D7d9368603412a2,
        0xc31f496aaE237599872ac78611b245Bfe70fB06e,
        0x799b35467C53F388D0c41D5f4EFFf8bAd7b33e96,
        0xdd571E39aa0DF0bf142f6b81CBA5923dDacf06a7,
        0x44b4e01c249e35B2803f947C5CcB9868C3421437,
        0xE94aFF2Bd6A12DD16C21648Cae71D2B47E405a9C,
        0x608E4105e49ce2562521e31936815e2E20dA6609,
        0x82d69F18C66278D59507610274DbC070F30AB009,
        0x3A34c9bE0C5E19F39A9774b9E7e5eB4c7f763A61,
        0x21d908322813a195164589068727E605202c422b,
        0x90D722865c4Bd91d98a78ba142ffFD3b29c13347,
        0x69AB5EA1B86D1341269F012115Ac914a334A1Ae3,
        0x2A1645283a69A35B3CC44063d71ad3e6B9b7463b,
        0xf95E265F70874a0261F8F4a59822451c86f65b68,
        0x417987107C146B5596b02d2fEa261111143e9f9c,
        0x86F8d09EfD8ad2c85Fee831f2730d1766A39ec18,
        0x915cCdA60B089f4dc8715d5acB58CEA9273D927F,
        0xC23D76D68b998E029Cf8476C83853e77C69fd38D,
        0xF184023BD59E3BC0aD515306DA0891D82A6ed3C0,
        0x46fBC1BB799C1D71548f69Ad0603DCcDb52d8341,
        0xa6aEEf4455376470ddB62299857b59eF7DD9384b,
        0x9bbF31E99F30c38a5003952206C31EEa77540BeF,
        0x4e70b989742212c4C82311A1C4C426489CC6f96E,
        0x3D92968C1cb89Dc769E75Ba7C0D9Cd65505e021E,
        0xb940c40EE41Aa18972A9CE04112B500E108a997b,
        0x356eA7e4cF3D087Dc1D6F9690b6a2C1f5a00D213,
        0xFFCCF1e9082e6eA712Cb1D93827a6ac31473a7C2,
        0x5ba791B15Df1fc00d50824F489e812dE0949DFAE,
        0x91BF9728dC9768c62d82df52D95C72b7Ff6caE47,
        0x104072634cE258bb3F8670e71A8F93fb77F523D7,
        0x41Dc0b6B95412f983ea111F4Cacbc0ED7076Cef0,
        0x51C57E88473A6D00db590C007174141056B89757,
        0x613E8479F220D60f897e0C8bA85De6563c23B747,
        0x0897f99a36aB964CfD12AC66335602BA9C9FD82B
    ];
    // Reward distributors array
    address[] public gauges = [
        0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A,
        0x3C0FFFF15EA30C35d7A85B85c0782D6c94e1d238,
        0x182B723a58739a9c974cFDB385ceaDb237453c28,
        0x72E158d38dbd50A483501c24f792bDAAA3e7D55C,
        0x9B8519A9a00100720CCdC8a120fBeD319cA47a14,
        0x824F13f1a2F29cFEEa81154b46C0fc820677A637,
        0xDeFd8FdD20e0f34115C7018CCfb655796F6B2168,
        0xd8b712d29381748dB89c36BCa0138d7c75866ddF,
        0x903dA6213a5A12B61c821598154EfAd98C3B20E4,
        0x63d9f3aB7d0c528797A12a0684E50C397E9e79dC,
        0xC95bdf13A08A547E4dD9f29B00aB7fF08C5d093d,
        0x8Fa728F393588E8D8dD1ca397E9a710E53fA553a,
        0x29284d30bcb70e86a6C3f84CbC4de0Ce16b0f1CA,
        0x1E212e054d74ed136256fc5a5DDdB4867c6E003F,
        0x1cEBdB0856dd985fAe9b8fEa2262469360B8a3a6,
        0x66ec719045bBD62db5eBB11184c18237D3Cc2E62,
        0x02246583870b36Be0fEf2819E1d3A771d6C07546,
        0xB81465Ac19B9a57158a79754bDaa91C60fDA91ff,
        0x60355587a8D4aa67c2E64060Ab36e566B9bCC000,
        0x95d16646311fDe101Eb9F897fE06AC881B7Db802,
        0xdB7cbbb1d5D5124F86E92001C9dFDC068C05801D,
        0xa9A9BC60fc80478059A83f516D5215185eeC2fc0,
        0x03fFC218C7A9306D21193565CbDc4378952faA8c,
        0x663FC22e92f26C377Ddf3C859b560C4732ee639a,
        0x4fb13b55D6535584841dbBdb14EDC0258F7aC414,
        0xCFc25170633581Bf896CB6CDeE170e3E3Aa59503,
        0x4329c8F09725c0e3b6884C1daB1771bcE17934F9,
        0xf6D7087D4Ae4dCf85956d743406E63cDA74D99AD,
        0x740BA8aa0052E07b925908B380248cb03f3DE5cB,
        0x9f57569EaA61d427dEEebac8D9546A745160391C,
        0x28216318D85b2D6d8c2cB38eed08001d9348803b,
        0xBE266d68Ce3dDFAb366Bb866F4353B6FC42BA43c,
        0xD5bE6A05B45aEd524730B6d1CC05F59b021f6c87,
        0xF9F46eF781b9C7B76e8B505226d5E0e0E7FE2f04,
        0xAd96E10123Fa34a01cf2314C42D75150849C9295,
        0x5980d25B4947594c26255C0BF301193ab64ba803,
        0x2932a86df44Fe8D2A706d8e9c5d51c24883423F5,
        0xa8Ea11465A1375BF42463C3B613dFC54248b9C7B,
        0x805Aef679B1379Ee1d24c52158E7F56098D199D9,
        0x6a69FfD1353Fa129f7F9932BB68Fa7bE88F3888A,
        0xACc9F5CEDC631180a2aD4C945377930fCFCC782F,
        0x7970489a543FB237ABab63d62524d8A5CE165B86,
        0xe5d5Aa1Bbe72F68dF42432813485cA1Fc998DE32,
        0x98ff4EE7524c501F582C48b828277D2B42bbc894,
        0xcb7CEB005dce5743026cDDaD2364d74f594b95A4,
        0xfB18127c1471131468a1AaD4785c19678e521D86,
        0xEEBC06d495c96E57542A6d829184A907A02ef602,
        0xBdCA4F610e7101Cc172E2135ba025737B99AbD30,
        0x06B30D5F2341C2FB3F6B48b109685997022Bd272,
        0xd03BE91b1932715709e18021734fcB91BB431715,
        0x50161102a240b1456d770Dbb55c76d8dc2D160Aa,
        0x79F21BC30632cd40d2aF8134B469a0EB4C9574AA,
        0xfcAf4EC80a94a5409141Af16a1DcA950a6973a39,
        0x5c07440a172805d566Faf7eBAf16EF068aC05f43,
        0x4e6bB6B7447B7B2Aa268C16AB87F4Bb48BF57939,
        0x95f00391cB5EebCd190EB58728B4CE23DbFa6ac1,
        0x27cace18f661161661683bBA43933B2E6eB1741E,
        0x26F7786de3E6D9Bd37Fcf47BE6F2bC455a21b74A,
        0x0060E266c2AF65bfc4fd51b04c93d952DF805630,
        0x5fDdB41cF566F6305293B2c9ad0fAf70dEAF7992,
        0x7292AfC5d77F988c873ca18F73CD96636c4Ac145,
        0x96424E6b5eaafe0c3B36CA82068d574D44BE4e3c,
        0x688Eb2C49D352c9448049A2263CFcE63D0918d3e,
        0xF29FfF074f5cF755b55FbB3eb10A29203ac91EA2,
        0x85D44861D024CB7603Ba906F2Dc9569fC02083F6,
        0x298bf7b80a6343214634aF16EB41Bb5B9fC6A1F1,
        0x60d3d7eBBC44Dc810A743703184f062d00e6dB7e,
        0x533B5AeE744647C20e33653F03676c471bb8e67B,
        0x512a68DD5433563Bad526C8C2838c39deBc9a756,
        0xB3627140BEacb97f9CA52b34090352FdAfC77d72,
        0xFc58C946A2D541cfA29Ad8c16FC2994323e34458,
        0x71873000399dB5FDDcD8d953E0e6570a0cb4c50C,
        0xe39c817fe25Ac1A8Bd343A74037E3C90b09bEeEF,
        0xEcAD6745058377744c09747b2715c0170B5699e5,
        0xDe14d2B848a7a1373E155Cc4db9B649f4BE24296,
        0x8D867BEf70C6733ff25Cc0D1caa8aA6c38B24817,
        0x4e227d29b33B77113F84bcC189a6F886755a1f24,
        0x8b87c8d75a620Df2271eD06B161de6cf811221b6,
        0x5439Dda1cE6A4A5222dB85bB2cAf0AB32c815Be6,
        0x2DD2b7E07dD433B758B98A3889a63cbF48ef0D99,
        0x378e249F4F7007Bd90c2186240374D512B839770,
        0x20e783242415A589B7E533a46A24FDA240590a18,
        0x724476f141ED2DE4DA22eBDF435905dEf1118317,
        0xA6762d10D6471F778C9c6Ce21A38245e9387915e,
        0x277d1424a84B35ec0a8108482551b00b4fc1539b,
        0x2d5727a90eDd42B4d666fF773C7809215284c326,
        0xf69Fb60B79E463384b40dbFDFB633AB5a863C9A2,
        0x35aD1ACf0C4BE5d4Ba11342128D440fDb9e189eb,
        0x9B7BD68e32B29ce0669dAa9b4c4DCe44a9faB80C,
        0x296Cb319665031Ac9E40b373d0C84e7D5fdAB80d,
        0x25707E5FE03dEEdc9Bc7cDD118f9d952C496FeBe,
        0x1Ee8f8B504E99a0fCD3A32D38aa9968750A708aD,
        0x8A111B47B31bBa40C2F0D2f9a8Cf6B6C4B50114E,
        0x63DC752E11D4c9D0f2160DA20EdF2111FECB0a66
    ];

    function run() public {
        vm.startBroadcast(DEPLOYER);

        /// 1. Deploy the Strategy and Proxy.
        stratImplementation = new CRVStrategy(address(this), SD_VOTER_PROXY, VE_CRV, REWARD_TOKEN, MINTER);

        // Clone strategy
        address _proxy = address(new ERC1967Proxy(address(stratImplementation), ""));

        strategy = CRVStrategy(payable(_proxy));

        /// 2. Initialize the Strategy.
        strategy.initialize(DEPLOYER);

        vm.stopBroadcast();

        /// 3. Set the strategy as `strategy` in the locker. This mean the depositor would not work anymore.
        /// TODO: This action requires multisig action. The locker governance is the old strategy.
        /// Now we have the old strategy as `governance` and the new strategy as `strategy`
        vm.broadcast(locker.governance());
        /// By being strategy, we can use the execute function.
        locker.setStrategy(payable(address(strategy)));

        vm.startBroadcast(DEPLOYER);

        /// 4. Deploy ConvexMinimalProxy Factory.
        implementation = new ConvexImplementation();
        factory = new ConvexMinimalProxyFactory(
            BOOSTER, address(strategy), REWARD_TOKEN, FALLBACK_REWARD_TOKEN, address(implementation)
        );

        /// 5. Deploy the Optimizer and set it in the strategy.
        optimizer = new Optimizer(address(strategy), address(factory));
        strategy.setOptimizer(address(optimizer));

        /// 5. Transfer the ownership of the new strategy to governance.
        /// It should be accepted after all the scripts are executed.
        strategy.transferGovernance(GOVERNANCE);

        vm.stopBroadcast();

        /// 6. For each pool:
        /// . Toggle the vault to the new strategy.
        /// . Set the reward distributor to the new strategy.
        require(rewardDistributors.length == gauges.length, "Invalid length");

        for (uint256 i = 0; i < rewardDistributors.length; i++) {
            IOldStrategy oldStrategy = IOldStrategy(locker.governance());
            require(oldStrategy.multiGauges(gauges[i]) == rewardDistributors[i], "Invalid distributor");

            address token = ILiquidityGauge(gauges[i]).lp_token();
            address vault = ILiquidityGauge(rewardDistributors[i]).staking_token();

            /// . Toggle the vault to the new strategy.
            vm.broadcast(DEPLOYER);
            strategy.toggleVault(vault);

            vm.broadcast(DEPLOYER);
            strategy.setGauge(token, gauges[i]);

            vm.broadcast(DEPLOYER);
            strategy.setRewardDistributor(gauges[i], rewardDistributors[i]);

            /// Last step is to migrate the funds from the old strategy to the new one.
            vm.broadcast(GOVERNANCE);
            IVault(vault).setCurveStrategy(address(strategy));
        }

        /// This are the steps to migrate from the strategy to the new.
        /// Next missing steps:
        /// - For each reward distributor, update all distributor for any extra tokens to the strategy.
        /// - Move set the new strategy as governance in the locker.
        /// - Set the new depositor as strategy in the locker.
    }
}
