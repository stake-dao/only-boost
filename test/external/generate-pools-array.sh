#!/bin/bash

# Check input
if [[ -z "$1" ]]; then
    echo "Usage: $0 path_to_json_file"
    exit 1
fi

json_file=$1

# Parse the JSON and collect rewardDistributor values into an array
reward_distributors=($(jq -r '.[].rewardDistributor' "$json_file"))

# Parse the JSON and collect rewardDistributor values into an array
gauges=($(jq -r '.[].gauge' "$json_file"))

# Start of the solidity file
cat <<EOF
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;


contract RewardDistributors {

// Reward distributors array
address[] public rewardDistributors = [
EOF

# Loop through the array and print each address
for ((i = 0; i < ${#reward_distributors[@]}; i++)); do
    if [[ $i -eq $((${#reward_distributors[@]} - 1)) ]]; then
        echo "    ${reward_distributors[$i]}"
    else
        echo "    ${reward_distributors[$i]},"
    fi
done

# End of the array in the solidity file
echo "];"

cat <<EOF
// Reward distributors array
address[] public gauges = [
EOF

# Loop through the array and print each address
# Loop through the array and print each address
for ((i = 0; i < ${#gauges[@]}; i++)); do
    if [[ $i -eq $((${#gauges[@]} - 1)) ]]; then
        echo "    ${gauges[$i]}"
    else
        echo "    ${gauges[$i]},"
    fi
done

# End of the array in the solidity file
echo "];"

cat <<EOF
}
EOF

# Now you have a solidity file named `rewardDistributors.sol`
# with an array of all reward distributor addresses
