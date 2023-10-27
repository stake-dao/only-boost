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

import "test/Base.t.sol";
import "test/integration/only-boost/OnlyBoost.t.sol";

EOF

# Parse the JSON and generate the solidity contracts
jq -r '.[] | "uint256 constant \(.name)_PID = \(.pid);\naddress constant \(.name)_REWARD_DISTRIBUTOR = \(.rewardDistributor);\n\ncontract \(.name)_OnlyBoost_Test is OnlyBoost_Test(\(.name)_PID, \(.name)_REWARD_DISTRIBUTOR) {}\n"' $json_file
