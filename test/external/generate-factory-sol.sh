#!/bin/bash

# Check input
if [[ -z "$1" ]]; then
    echo "Usage: $0 path_to_json_file"
    exit 1
fi

json_file=$1

# Start of the solidity file
cat <<EOF
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "test/pool-factory/Staking.t.sol";
import "test/pool-factory/PoolFactory.t.sol";

EOF

# Parse the JSON and generate the solidity contracts
jq -r '.[] | "uint256 constant \(.name)_PID = \(.pid);\n\ncontract \(.name)_Factory_Test is PoolFactory_Test(\(.name)_PID) {}\n\ncontract \(.name)_Staking_Test is Staking_Test(\(.name)_PID) {}\n"' $json_file
