import json, os
from web3 import Web3
from dotenv import load_dotenv


def load_abi(file_path):
    with open(file_path, "r") as f:
        return json.load(f)


def load_pools(file_path):
    with open(file_path, "r") as f:
        return json.load(f)


def initialize_web3():
    load_dotenv()
    INFURA_URL = "https://mainnet.infura.io/v3/" + os.getenv("INFURA_KEY")
    return Web3(Web3.HTTPProvider(INFURA_URL))


def get_contract(w3, address, abi):
    return w3.eth.contract(address=address, abi=abi)


def create_batches(transactions, batch_size=150):
    for i in range(0, len(transactions), batch_size):
        yield transactions[i : i + batch_size]


def main():
    w3 = initialize_web3()

    only_boost_abi = load_abi("test/external/ob.json")
    controller_abi = load_abi("test/external/controller.json")
    lgv5_abi = load_abi("test/external/lgv5.json")

    batch_template = load_abi("test/external/batch_set_strategy.json")

    CONTROLLER = "0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB"

    STRATEGY = "0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd"
    SDT = "0x73968b9a57c6E53d41345FD57a6E6ae27d6CDB2F"
    LOCKER = "0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6"
    ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

    strategy_contract = get_contract(w3, STRATEGY, only_boost_abi)
    controller = get_contract(w3, CONTROLLER, controller_abi)

    pool_length = controller.functions.n_gauges().call()

    transactions = []

    for i in range(pool_length):
        gauge = controller.functions.gauges(i).call()
        multi_gauge = strategy_contract.functions.rewardDistributors(gauge).call()

        if multi_gauge == ZERO_ADDRESS:
            continue

        print(f"MultiGauge: {multi_gauge}")

        multi_gauge_contract = get_contract(w3, multi_gauge, lgv5_abi)

        reward_count = multi_gauge_contract.functions.reward_count().call()

        for j in range(0, reward_count):
            reward = multi_gauge_contract.functions.reward_tokens(j).call()

            if reward == SDT:
                continue

            distributor = multi_gauge_contract.functions.reward_data(reward).call()[1]

            if distributor != STRATEGY:
                print(
                    f"Reward: {reward}",
                    f"Distributor: {distributor}",
                    f"Multigauge: {multi_gauge}",
                )
                transactions.append({reward, multi_gauge})

    print("Number of transactions:", len(transactions))


if __name__ == "__main__":
    main()
