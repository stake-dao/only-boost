// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;
/*
▄▄▄█████▓ ██░ ██ ▓█████     ██░ ██ ▓█████  ██▀███  ▓█████▄ 
▓  ██▒ ▓▒▓██░ ██▒▓█   ▀    ▓██░ ██▒▓█   ▀ ▓██ ▒ ██▒▒██▀ ██▌
▒ ▓██░ ▒░▒██▀▀██░▒███      ▒██▀▀██░▒███   ▓██ ░▄█ ▒░██   █▌
░ ▓██▓ ░ ░▓█ ░██ ▒▓█  ▄    ░▓█ ░██ ▒▓█  ▄ ▒██▀▀█▄  ░▓█▄   ▌
  ▒██▒ ░ ░▓█▒░██▓░▒████▒   ░▓█▒░██▓░▒████▒░██▓ ▒██▒░▒████▓ 
  ▒ ░░    ▒ ░░▒░▒░░ ▒░ ░    ▒ ░░▒░▒░░ ▒░ ░░ ▒▓ ░▒▓░ ▒▒▓  ▒ 
    ░     ▒ ░▒░ ░ ░ ░  ░    ▒ ░▒░ ░ ░ ░  ░  ░▒ ░ ▒░ ░ ▒  ▒ 
  ░       ░  ░░ ░   ░       ░  ░░ ░   ░     ░░   ░  ░ ░  ░ 
          ░  ░  ░   ░  ░    ░  ░  ░   ░  ░   ░        ░    
                                                    ░      
              .,;>>%%%%%>>;,.
           .>%%%%%%%%%%%%%%%%%%%%>,.
         .>%%%%%%%%%%%%%%%%%%>>,%%%%%%;,.
       .>>>>%%%%%%%%%%%%%>>,%%%%%%%%%%%%,>>%%,.
     .>>%>>>>%%%%%%%%%>>,%%%%%%%%%%%%%%%%%,>>%%%%%,.
   .>>%%%%%>>%%%%>>,%%>>%%%%%%%%%%%%%%%%%%%%,>>%%%%%%%,
  .>>%%%%%%%%%%>>,%%%%%%>>%%%%%%%%%%%%%%%%%%,>>%%%%%%%%%%.
  .>>%%%%%%%%%%>>,>>>>%%%%%%%%%%'..`%%%%%%%%,;>>%%%%%%%%%>%%.
.>>%%%>>>%%%%%>,%%%%%%%%%%%%%%.%%%,`%%%%%%,;>>%%%%%%%%>>>%%%%.
>>%%>%>>>%>%%%>,%%%%%>>%%%%%%%%%%%%%`%%%%%%,>%%%%%%%>>>>%%%%%%%.
>>%>>>%%>>>%%%%>,%>>>%%%%%%%%%%%%%%%%`%%%%%%%%%%%%%%%%%%%%%%%%%%.
>>%%%%%%%%%%%%%%,>%%%%%%%%%%%%%%%%%%%'%%%,>>%%%%%%%%%%%%%%%%%%%%%.
>>%%%%%%%%%%%%%%%,>%%%>>>%%%%%%%%%%%%%%%,>>%%%%%%%%>>>>%%%%%%%%%%%.
>>%%%%%%%%;%;%;%%;,%>>>>%%%%%%%%%%%%%%%,>>>%%%%%%>>;";>>%%%%%%%%%%%%.
`>%%%%%%%%%;%;;;%;%,>%%%%%%%%%>>%%%%%%%%,>>>%%%%%%%%%%%%%%%%%%%%%%%%%%.
 >>%%%%%%%%%,;;;;;%%>,%%%%%%%%>>>>%%%%%%%%,>>%%%%%%%%%%%%%%%%%%%%%%%%%%%.
 `>>%%%%%%%%%,%;;;;%%%>,%%%%%%%%>>>>%%%%%%%%,>%%%%%%'%%%%%%%%%%%%%%%%%%%>>.
  `>>%%%%%%%%%%>,;;%%%%%>>,%%%%%%%%>>%%%%%%';;;>%%%%%,`%%%%%%%%%%%%%%%>>%%>.
   >>>%%%%%%%%%%>> %%%%%%%%>>,%%%%>>>%%%%%';;;;;;>>,%%%,`%     `;>%%%%%%>>%%
   `>>%%%%%%%%%%>> %%%%%%%%%>>>>>>>>;;;;'.;;;;;>>%%'  `%%'          ;>%%%%%>
    >>%%%%%%%%%>>; %%%%%%%%>>;;;;;;''    ;;;;;>>%%%                   ;>%%%%
    `>>%%%%%%%>>>, %%%%%%%%%>>;;'        ;;;;>>%%%'                    ;>%%%
     >>%%%%%%>>>':.%%%%%%%%%%>>;        .;;;>>%%%%                    ;>%%%'
     `>>%%%%%>>> ::`%%%%%%%%%%>>;.      ;;;>>%%%%'                   ;>%%%'
      `>>%%%%>>> `:::`%%%%%%%%%%>;.     ;;>>%%%%%                   ;>%%'
       `>>%%%%>>, `::::`%%%%%%%%%%>,   .;>>%%%%%'                   ;>%'
        `>>%%%%>>, `:::::`%%%%%%%%%>>. ;;>%%%%%%                    ;>%,
         `>>%%%%>>, :::::::`>>>%%%%>>> ;;>%%%%%'                     ;>%,
          `>>%%%%>>,::::::,>>>>>>>>>>' ;;>%%%%%                       ;%%,
            >>%%%%>>,:::,%%>>>>>>>>'   ;>%%%%%.                        ;%%
             >>%%%%>>``%%%%%>>>>>'     `>%%%%%%.
             >>%%%%>> `@@a%%%%%%'     .%%%%%%%%%.
             `a@@a%@'    `%a@@'       `a@@a%a@@a
 */

import "src/shutdown/v1/BaseShutdownStrategy.sol";

import {IStrategy} from "src/interfaces/IStrategy.sol";
import {ILiquidityGauge} from "src/interfaces/ILiquidityGauge.sol";
import {ReentrancyGuard} from "solady/src/utils/ReentrancyGuard.sol";

/// @notice Strategy contract, supporting Shutdown.
contract BalancerShutdownStrategy is Ownable2Step, BaseShutdownStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Address of the strategy.
    /// @dev It contains most of the storage of the strategy.
    address public constant STRATEGY = 0x873b031Ea6E4236E44d933Aae5a66AF6d4DA419d;

    /// @notice Address of the BAL token
    address public constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;

    /// @notice Address of the BAL minter
    address public constant BAL_MINTER = 0x239e55F427D44C3cc793f49bFB507ebe76638a2b;

    /// @notice Error when the BAL mint failed
    error MINT_FAILED();

    /// @notice Error when the BAL transfer failed
    error TRANSFER_FAILED();

    /// @notice Event when BAL is claimed
    event Claimed(address indexed gauge, address indexed token, uint256 amount);

    constructor(address _locker, address _gateway, address _governance)
        BaseShutdownStrategy(_locker, _gateway, _governance)
    {}

    function claim(address _token) external nonReentrant {
        address gauge = IStrategy(STRATEGY).gauges(_token);
        if (gauge == address(0)) revert ADDRESS_ZERO();
        if (isShutdown[gauge]) revert SHUTDOWN();

        /// 1. Snapshot the BAL balance.
        uint256 snapshot = IERC20(BAL).balanceOf(address(LOCKER));

        /// 2. Claim BAL through the BAL minter contract.
        if (!_executeTransaction(BAL_MINTER, abi.encodeWithSignature("mint(address)", gauge))) revert MINT_FAILED();

        /// 3. Calculate the minted BAL.
        uint256 minted = IERC20(BAL).balanceOf(address(LOCKER)) - snapshot;

        /// 4. Transfer the minted BAL to the strategy.
        if (!_executeTransaction(BAL, abi.encodeWithSignature("transfer(address,uint256)", address(this), minted))) {
            revert TRANSFER_FAILED();
        }

        /// 5. Distribute BAL.
        uint256 net = _chargeProtocolFees(BAL, minted);

        /// 6. Approve the reward distributor.
        address rewardDistributor = IStrategy(STRATEGY).multiGauges(gauge);

        /// 7. Approve the reward distributor.
        IERC20(BAL).safeApprove(rewardDistributor, net);

        /// 8. Deposit the BAL to the gauge.
        ILiquidityGauge(rewardDistributor).deposit_reward_token(BAL, net);

        /// 9. Mark the gauge as shutdown.
        isShutdown[gauge] = true;

        emit Claimed(gauge, BAL, minted);
    }
}
