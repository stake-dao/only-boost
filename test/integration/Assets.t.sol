// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "test/Base.t.sol";
import "test/proxy/Deposit.t.sol";

uint256 constant _3CRV_PID = 9;
address constant _3CRV_REWARD_DISTRIBUTOR = 0xf99FD99711671268EE557fEd651EA45e34B2414f;

contract _3CRV_Deposit_Test is OnlyBoost_Test(_3CRV_PID, _3CRV_REWARD_DISTRIBUTOR) {}

uint256 constant _CNC_ETH_PID = 152;
address constant _CNC_ETH_REWARD_DISTRIBUTOR = 0xE2568D65EeD31E6772CEf183f537032efEb68c23;

contract _CNC_ETH_Deposit_Test is OnlyBoost_Test(_CNC_ETH_PID, _CNC_ETH_REWARD_DISTRIBUTOR) {}

uint256 constant _SDT_ETH_PID = 131;
address constant _SDT_ETH_REWARD_DISTRIBUTOR = 0xB3a33E69582623F650e54Cc1cf4e439473A28D26;

contract _SDT_ETH_Deposit_Test is OnlyBoost_Test(_SDT_ETH_PID, _SDT_ETH_REWARD_DISTRIBUTOR) {}
