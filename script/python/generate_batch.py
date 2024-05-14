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


def create_batches(transactions, batch_size=25):
    for i in range(0, len(transactions), batch_size):
        yield transactions[i : i + batch_size]


def main():
    w3 = initialize_web3()

    only_boost_abi = load_abi("test/external/ob.json")
    strategy_abi = load_abi("test/external/strategy.json")
    vault_abi = load_abi("test/external/vault.json")
    reward_distributor_abi = load_abi("test/external/lgv5.json")
    executor_abi = load_abi("test/external/executor.json")
    locker_abi = load_abi("test/external/crv_locker.json")
    batch_template = load_abi("test/external/batch_set_strategy.json")

    # Load pools
    pools = load_pools("script/python/pools_migration.json")

    CRV = "0xD533a949740bb3306d119CC777fa900bA034cd52"

    STRATEGY = "0x69D61428d089C2F35Bf6a472F540D0F82D1EA2cd"
    DEPOSITOR = "0x88C88Aa6a9cedc2aff9b4cA6820292F39cc64026"

    LOCKER = "0x52f541764E6e90eeBc5c21Ff570De0e2D63766B6"
    OLD_STRATEGY = "0x20F1d4Fed24073a9b9d388AfA2735Ac91f079ED6"
    VOTER = "0x20b22019406Cf990F0569a6161cf30B8e6651dDa"

    strategy_contract = get_contract(w3, STRATEGY, only_boost_abi)
    voter_contract = get_contract(w3, VOTER, executor_abi)
    old_strategy_contract = get_contract(w3, OLD_STRATEGY, strategy_abi)
    locker_contract = get_contract(w3, LOCKER, locker_abi)

    GOVERNANCE = "0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063"

    transactions = []

    print(len(pools))

    for pool in pools:
        # For the first pool, we need set the new strategy as "strategy" in the locker
        if pool == pools[0]:
            locker_data = locker_contract.functions.setStrategy(STRATEGY)

            locker_data = locker_contract.encodeABI("setStrategy", [STRATEGY])
            strategy_data = old_strategy_contract.encodeABI(
                "execute", [LOCKER, 0, locker_data]
            )
            voter_data = voter_contract.encodeABI(
                "execute", [OLD_STRATEGY, 0, strategy_data]
            )

            transactions.append({"to": VOTER, "value": "0", "data": voter_data})

        print("Generating transaction for pool: ", pool["vault"])

        vault_address = pool["vault"]
        reward_distributor_address = pool["rewardDistributor"]
        vault_contract = get_contract(w3, vault_address, vault_abi)
        reward_distributor_contract = get_contract(
            w3, reward_distributor_address, reward_distributor_abi
        )

        data = vault_contract.encodeABI("setCurveStrategy", [STRATEGY])

        transactions.append({"to": vault_address, "value": "0", "data": data})

        data = reward_distributor_contract.encodeABI(
            "set_reward_distributor", [CRV, STRATEGY]
        )

        transactions.append(
            {"to": reward_distributor_address, "value": "0", "data": data}
        )

        # For the last pool, we need to set the new strategy as "governance" of the locker
        # and put back the depositor as "strategy"
        if pool == pools[-1]:

            locker_data = locker_contract.encodeABI("setGovernance", [STRATEGY])
            strategy_data = old_strategy_contract.encodeABI(
                "execute", [LOCKER, 0, locker_data]
            )
            voter_data = voter_contract.encodeABI(
                "execute", [OLD_STRATEGY, 0, strategy_data]
            )

            accept_ownership_data = strategy_contract.encodeABI("acceptGovernance")

            set_depositor_data = locker_contract.encodeABI("setStrategy", [DEPOSITOR])

            transactions.append({"to": VOTER, "value": "0", "data": voter_data})

            new_strategy_data = strategy_contract.encodeABI(
                "execute", [LOCKER, 0, set_depositor_data]
            )

            transactions.append(
                {"to": STRATEGY, "value": "0", "data": accept_ownership_data}
            )

            transactions.append(
                {"to": STRATEGY, "value": "0", "data": new_strategy_data}
            )

    print("Number of transactions:", len(transactions))

    # Create batches and save to JSON
    for idx, batch_transactions in enumerate(create_batches(transactions), start=1):
        batch_template["transactions"] = batch_transactions
        with open(f"script/batchs/batch_set_strategy_{idx}.json", "w") as f:
            json.dump(batch_template, f, indent=4)


if __name__ == "__main__":
    main()
