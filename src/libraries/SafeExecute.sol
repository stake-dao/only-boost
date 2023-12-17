/// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ILocker} from "src/interfaces/ILocker.sol";

library SafeExecute {
    error CALL_FAILED();

    function safeExecute(ILocker locker, address to, uint256 value, bytes memory data)
        internal
        returns (bool success)
    {
        (success,) = locker.execute(to, value, data);
        if (!success) revert CALL_FAILED();
    }

    function safeExecuteTransfer(ILocker locker, address to, address recipient, uint256 amount)
        internal
        returns (bool success)
    {
        bytes memory returnData;
        (success, returnData) = locker.execute(to, 0, abi.encodeWithSignature("transfer(address,uint256)", recipient, amount));

        if (!success) revert CALL_FAILED();
        if (returnData.length != 0 && !abi.decode(returnData, (bool))) revert CALL_FAILED();
    }
}
