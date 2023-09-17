// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "test/Base.t.sol";
import "test/integration/curve-strategy/deposits/Deposit.t.sol";

address constant _3CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
address constant _3CRV_GAUGE = 0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A;

contract _3CRV_Deposit_Test is Deposit_Test(_3CRV, _3CRV_GAUGE) {}

address constant _CNC_ETH = 0xF9835375f6b268743Ea0a54d742Aa156947f8C06;
address constant _CNC_ETH_GAUGE = 0x5A8fa46ebb404494D718786e55c4E043337B10bF;

contract _CNC_ETH_Deposit_Test is Deposit_Test(_CNC_ETH, _CNC_ETH_GAUGE) {}

address constant _SDT_ETH = 0x6359B6d3e327c497453d4376561eE276c6933323;
address constant _SDT_ETH_GAUGE = 0x60355587a8D4aa67c2E64060Ab36e566B9bCC000;

contract _SDT_ETH_Deposit_Test is Deposit_Test(_SDT_ETH, _SDT_ETH_GAUGE) {}
