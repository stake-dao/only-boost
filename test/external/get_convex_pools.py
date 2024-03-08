import os, json, requests
from web3 import Web3
from dotenv import load_dotenv

load_dotenv()

BOOSTER = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31"
STRATEGY = "0x20F1d4Fed24073a9b9d388AfA2735Ac91f079ED6"
CONTROLLER = "0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB"

# Addresses that was used to test new strategies with small deposits.
BLACKLIST = [
    "0x6Ae7bf291028CCf52991BD020D2Dc121b40bce2A",
    "0xb957DccaA1CCFB1eB78B495B499801D591d8a403",
    "0xb4d27B87A09aB76C47e342535A309A1176051481",
    "0x41717436744232Fb66E85fFAf388a8a33BC7397a",
    "0x54c9cB3AC40EF11C56565e8490e7C3b4b17582AF",
    "0xb36a0671B3D49587236d7833B01E79798175875f",
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


def main():
    return build_pools()


__name__ == "__main__" and main()
