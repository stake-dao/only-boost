import os, json, requests
from web3 import Web3
from dotenv import load_dotenv

load_dotenv()

BOOSTER = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31"
STRATEGY = "0x20F1d4Fed24073a9b9d388AfA2735Ac91f079ED6"
CONTROLLER = "0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB"

# Addresses that was used to test new strategies with small deposits.
BLACKLIST = [
"0x6ae7bf291028ccf52991bd020d2dc121b40bce2a",
"0x54c9cb3ac40ef11c56565e8490e7c3b4b17582af",
"0x074c3de651d6ecdbf79164ab8392ed388aaccb04",
"0x41717436744232fb66e85ffaf388a8a33bc7397a",
"0xb4d27b87a09ab76c47e342535a309a1176051481"
]

ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

with open("test/external/controller.json", "r") as f:
    CONTROLLER_ABI = json.load(f)

with open("test/external/booster.json", "r") as f:
    BOOSTER_ABI = json.load(f)

with open("test/external/lgv5.json", "r") as f:
    GAUGE_ABI = json.load(f)

with open("test/external/strategy.json", "r") as f:
    STRATEGY_ABI = json.load(f)

# Initialize Web3
INFURA_URL = "https://mainnet.infura.io/v3/" + os.getenv("INFURA_KEY")
w3 = Web3(Web3.HTTPProvider(INFURA_URL))

# Query all pools on Convex.
booster = w3.eth.contract(address=BOOSTER, abi=BOOSTER_ABI)
strategy = w3.eth.contract(address=STRATEGY, abi=STRATEGY_ABI)
controller = w3.eth.contract(address=CONTROLLER, abi=CONTROLLER_ABI)


def get_all_pools():
    pool_length = booster.functions.poolLength().call()

    pool_list = []

    for i in range(pool_length):
        pool = booster.functions.poolInfo(i).call()

        pool_list.append(
            {"pid": i, "rewardDistributor": ZERO_ADDRESS, "name": "_" + str(i)}
        )

    # Dump to JSON
    with open("test/external/all_pools.json", "w") as f:
        json.dump(pool_list, f, indent=4)


def build_pools():
    pool_length = controller.functions.n_gauges().call()

    pool_list = []

    for i in range(pool_length):
        gauge = controller.functions.gauges(i).call()
        multi_gauge = strategy.functions.multiGauges(gauge).call()

        if multi_gauge != ZERO_ADDRESS:
            _mg = w3.eth.contract(address=multi_gauge, abi=GAUGE_ABI)
            ts = _mg.functions.totalSupply().call()

            balanceOf = 0
            for b in BLACKLIST:
                b = w3.to_checksum_address(b)
                balanceOf += _mg.functions.balanceOf(b).call()

            if ts > 0 and balanceOf > 0 and ts == balanceOf:
                print("Blacklisted: ", ts, balanceOf, ts == balanceOf, multi_gauge, i)
                continue

            if ts > 0:
                print("Compatible: ", multi_gauge, " " + str(i) + " " + str(ts))
                pool_list.append(
                    {
                        "pid": i,
                        "gauge": gauge,
                        "rewardDistributor": multi_gauge,
                        "name": "_" + str(i),
                    }
                )

    # Dump to JSON
    with open("test/external/sd_pools.json", "w") as f:
        json.dump(pool_list, f, indent=4)

    print(len(pool_list))


def check_holders():
    pool_length = controller.functions.n_gauges().call()

    pool_list = []

    for i in range(pool_length):
        gauge = controller.functions.gauges(i).call()
        multi_gauge = strategy.functions.multiGauges(gauge).call()

        if multi_gauge != ZERO_ADDRESS:
            _mg = w3.eth.contract(address=multi_gauge, abi=GAUGE_ABI)
            address = test_api(multi_gauge)

            if address != "0x":
                if address not in pool_list:
                    print("Found: ", address)
                    pool_list.append(address)

    print(len(pool_list))


def test_api(contract):
    # DeBank API endpoint
    url = "https://api.chainbase.online/v1/token/top-holders"

    # Headers for the request
    headers = {
        "accept": "application/json",
        "x-api-key": "2dOtr68sLIpZq62d2Y1ll5BNugq"  # Replace this with your actual access key
    }

    # Parameters for the request
    params = {
        "chain_id": "1",
        "contract_address": contract
    }

    # Make the GET request to the DeBank API
    response = requests.get(url, headers=headers, params=params)

    # Check if the request was successful
    if response.status_code == 200:
        # Parse the JSON response
        data = response.json()
        if(data["count"] == 1):
            return data["data"][0]["wallet_address"]
        else:
            return "0x"

    else:
        print(f"Failed to retrieve data, status code: {response.status_code}")


def main():
    # test_api("0xfA51194E8eafc40523574A65C1e4606E1432408B")
    # check_holders()
    return build_pools()


__name__ == "__main__" and main()
