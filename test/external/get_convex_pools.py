import os, json
from web3 import Web3
from dotenv import load_dotenv

load_dotenv()

BOOSTER = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31"
STRATEGY = "0x20F1d4Fed24073a9b9d388AfA2735Ac91f079ED6"
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

with open("test/external/booster.json", "r") as f:
    BOOSTER_ABI = json.load(f)

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

        pool_list.append(
            {"pid": i, "rewardDistributor": ZERO_ADDRESS, "name": "_" + str(i)}
        )

    # Dump to JSON
    with open("test/external/all_pools.json", "w") as f:
        json.dump(pool_list, f, indent=4)



def build_pools():
    pool_length = booster.functions.poolLength().call()

    pool_list = []

    for i in range(pool_length):
        pool = booster.functions.poolInfo(i).call()
        gauge = pool[2]

        multi_gauge = strategy.functions.multiGauges(gauge).call()
        if pool[5] == False and multi_gauge != ZERO_ADDRESS:
            pool_list.append(
                {"pid": i, "gauge": gauge,  "rewardDistributor": multi_gauge, "name": "_" + str(i)}
            )

    # Dump to JSON
    with open("test/external/sd_pools.json", "w") as f:
        json.dump(pool_list, f, indent=4)


def main():
    return build_pools()


__name__ == "__main__" and main()
