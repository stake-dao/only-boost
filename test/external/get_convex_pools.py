import os, json, requests
from web3 import Web3
from dotenv import load_dotenv

load_dotenv()

BOOSTER = "0xF403C135812408BFbE8713b5A23a04b3D48AAE31"
STRATEGY = "0x20F1d4Fed24073a9b9d388AfA2735Ac91f079ED6"
NEW_STRATEGY = "0x20F1d4Fed24073a9b9d388AfA2735Ac91f079ED6"
CONTROLLER = "0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB"

# Addresses that were used to test new strategies with small deposits.
BLACKLIST = [
    "0x6ae7bf291028ccf52991bd020d2dc121b40bce2a",
    "0x54c9cb3ac40ef11c56565e8490e7c3b4b17582af",
    "0x074c3de651d6ecdbf79164ab8392ed388aaccb04",
    "0x41717436744232fb66e85ffaf388a8a33bc7397a",
    "0xb4d27b87a09ab76c47e342535a309a1176051481",
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

with open("test/external/vault.json", "r") as f:
    VAULT_ABI = json.load(f)

with open("test/external/batch_set_strategy.json", "r") as f:
    BATCH = json.load(f)

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

    transactions = []

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
                vault = _mg.functions.staking_token().call()
                vault_contract = w3.eth.contract(address=vault, abi=VAULT_ABI)
                data = vault_contract.functions.setCurveStrategy(
                    STRATEGY
                ).build_transaction(
                    {"from": "0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063"}
                )[
                    "data"
                ]

                print("Building transaction for: ", multi_gauge, vault)

                transactions.append(
                    {
                        "to": vault,
                        "value": "0",
                        "data": data,
                    }
                )

    print(len(transactions))
    BATCH["transactions"] = transactions

    # Dump to JSON
    with open("test/external/batch_set_strategy.json", "w") as f:
        json.dump(BATCH, f, indent=4)
    # print(len(pool_list))


def main():
    pool_list = build_pools()


__name__ == "__main__" and main()
