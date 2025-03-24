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
contract PendleShutdownStrategy is Ownable2Step, BaseShutdownStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Address of the strategy.
    /// @dev It contains most of the storage of the strategy.
    address public constant STRATEGY = 0xA7641acBc1E85A7eD70ea7bCFFB91afb12AD0c54;

    /// @notice Address of the PENDLE token
    address public constant PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;

    /// @notice Error when the BAL mint failed
    error MINT_FAILED();

    /// @notice Error when the BAL transfer failed
    error TRANSFER_FAILED();

    /// @notice Error when the caller is not the vault
    error ONLY_VAULT();

    /// @notice Event when BAL is claimed
    event Claimed(address indexed gauge, address indexed token, uint256 amount);

    /// @notice Event when a token is withdrawn
    event Withdrawn(address indexed gauge, address indexed token, uint256 amount);

    modifier onlyVault() {
        if (!IStrategy(STRATEGY).vaults(msg.sender)) revert ONLY_VAULT();
        _;
    }

    constructor(address _locker, address _gateway, address _governance)
        BaseShutdownStrategy(_locker, _gateway, _governance)
    {}

    /// @dev Reproduces the claim function of the STRATEGY contract and shuts down the gauge.
    function claim(address _token) external nonReentrant {}

    function deposit(address, uint256) external pure {
        revert SHUTDOWN();
    }

    function withdraw(address _token, uint256 _amount, address _receiver) external onlyVault {
        _withdraw(_token, _amount, _receiver);
    }

    function claimProtocolFees() external {
        _claimProtocolFees(PENDLE);
    }

    //////////////////////////////////////////////////////
    /// --- DEPOSIT & WITHDRAWAL REWRITES
    //////////////////////////////////////////////////////

    /// @notice function to withdraw from a gauge
    /// @param _token token address
    /// @param _amount amount to withdraw
    function _withdraw(address _token, uint256 _amount, address _receiver) internal {
        address gauge = IStrategy(STRATEGY).gauges(_token);
        if (gauge == address(0)) revert ADDRESS_ZERO();
        if (isShutdown[gauge]) revert SHUTDOWN();

        IERC20(_token).safeTransfer(_receiver, _amount);

        emit Withdrawn(gauge, _token, _amount);
    }
}
