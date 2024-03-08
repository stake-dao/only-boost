import os, json
from web3 import Web3
from dotenv import load_dotenv

load_dotenv()

BOOSTER = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31"
STRATEGY = "0x20F1d4Fed24073a9b9d388AfA2735Ac91f079ED6"
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

with open("test/external/booster.json", "r") as f:
    BOOSTER_ABI = json.load(f)

with open("test/external/lgv5.json", "r") as f:
    REWARD_REICEIVER_ABI = json.load(f)

with open("test/external/strategy.json", "r") as f:
    STRATEGY_ABI = json.load(f)

# Initialize Web3
INFURA_URL = "https://mainnet.infura.io/v3/" + os.getenv("INFURA_KEY")
w3 = Web3(Web3.HTTPProvider(INFURA_URL))

# Query all pools on Convex.
booster = w3.eth.contract(address=BOOSTER, abi=BOOSTER_ABI)
strategy = w3.eth.contract(address=STRATEGY, abi=STRATEGY_ABI)


def get_all_pools():
    pool_length = booster.functions.poolLength().call()

    pool_list = []

    for i in range(pool_length):
        pool = booster.functions.poolInfo(i).call()
        gauge = pool[2]
        gauge = w3.eth.contract(address=gauge, abi=REWARD_REICEIVER_ABI)

        try:
            receiver = gauge.functions.rewards_receiver(BOOSTER).call()
            total_supply = gauge.functions.totalSupply().call()
            print("Compatible: ", gauge.address, " " + str(i))
            pool_list.append(
                {"pid": i, "gauge": gauge.address, "total_supply": total_supply}
            )
        except:
            print("Not compatible: ", gauge.address + " " + str(i))
            pass

    return pool_list


def main():
    pool = get_all_pools()

    # Filter by total supply sorted by total supply
    pool = sorted(pool, key=lambda x: x["total_supply"], reverse=True)

    for p in pool:
        print(p)


__name__ == "__main__" and main()
