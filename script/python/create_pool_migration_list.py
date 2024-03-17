import os
import json
from web3 import Web3
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Contract addresses and other constants
STRATEGY = "0x20F1d4Fed24073a9b9d388AfA2735Ac91f079ED6"
CONTROLLER = "0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB"
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

BLACKLIST = [
    "0x6ae7bf291028ccf52991bd020d2dc121b40bce2a",
    "0x54c9cb3ac40ef11c56565e8490e7c3b4b17582af",
    "0x074c3de651d6ecdbf79164ab8392ed388aaccb04",
    "0x41717436744232fb66e85ffaf388a8a33bc7397a",
    "0xb4d27b87a09ab76c47e342535a309a1176051481",
]


# Load contract ABIs
def load_abi(file_name):
    with open(f"test/external/{file_name}", "r") as f:
        return json.load(f)


CONTROLLER_ABI = load_abi("controller.json")
GAUGE_ABI = load_abi("lgv5.json")
STRATEGY_ABI = load_abi("strategy.json")
VAULT_ABI = load_abi("vault.json")

# Initialize Web3
INFURA_URL = "https://mainnet.infura.io/v3/" + os.getenv("INFURA_KEY")
w3 = Web3(Web3.HTTPProvider(INFURA_URL))

# Set up contracts
controller = w3.eth.contract(address=CONTROLLER, abi=CONTROLLER_ABI)
strategy = w3.eth.contract(address=STRATEGY, abi=STRATEGY_ABI)


def generate_pool_list():
    pool_length = controller.functions.n_gauges().call()
    pool_list = []

    for i in range(pool_length):
        gauge = controller.functions.gauges(i).call()
        multi_gauge = strategy.functions.multiGauges(gauge).call()
        if multi_gauge == ZERO_ADDRESS:
            continue

        _mg = w3.eth.contract(address=multi_gauge, abi=GAUGE_ABI)
        total_supply = _mg.functions.totalSupply().call()
        balance_of_blacklist = sum(
            _mg.functions.balanceOf(w3.to_checksum_address(b)).call() for b in BLACKLIST
        )

        if total_supply > 0 and total_supply != balance_of_blacklist:
            vault = _mg.functions.staking_token().call()
            pool_list.append(
                {"gauge": gauge, "vault": vault, "rewardDistributor": multi_gauge}
            )

    # Dump the list to JSON
    with open("pools_migration.json", "w") as f:
        json.dump(pool_list, f, indent=4)


if __name__ == "__main__":
    generate_pool_list()
