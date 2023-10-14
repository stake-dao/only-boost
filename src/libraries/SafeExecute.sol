/// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {ILocker} from "src/interfaces/ILocker.sol";

library SafeExecute {
    error CALL_FAILED();

    function safeExecute(ILocker locker, address to, uint256 value, bytes memory data)
        internal
        returns (bool success)
    {
        (success,) = locker.execute(to, value, data);
    }
}
