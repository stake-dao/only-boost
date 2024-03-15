import json, os
from web3 import Web3
from dotenv import load_dotenv

def load_abi(file_path):
    with open(file_path, 'r') as f:
        return json.load(f)

def load_pools(file_path):
    with open(file_path, 'r') as f:
        return json.load(f)

def initialize_web3():
    load_dotenv()
    INFURA_URL = "https://mainnet.infura.io/v3/" + os.getenv("INFURA_KEY")
    return Web3(Web3.HTTPProvider(INFURA_URL))

def get_contract(w3, address, abi):
    return w3.eth.contract(address=address, abi=abi)

def create_batches(transactions, batch_size=8):
    for i in range(0, len(transactions), batch_size):
        yield transactions[i:i + batch_size]

def main():
    w3 = initialize_web3()

    strategy_abi = load_abi("test/external/strategy.json")
    vault_abi = load_abi("test/external/vault.json")
    reward_distributor_abi = load_abi("test/external/lgv5.json")
    batch_template = load_abi("test/external/batch_set_strategy.json")
    pools = load_pools("script/python/pools_migration.json")  

    CRV = "0xD533a949740bb3306d119CC777fa900bA034cd52"

    # TODO: Replace with the new deployed strategy address
    STRATEGY = "0x20F1d4Fed24073a9b9d388AfA2735Ac91f079ED6"
    GOVERNANCE = "0xF930EBBd05eF8b25B1797b9b2109DDC9B0d43063"

    transactions = []

    print(len(pools))

    for pool in pools:
        print("Generating transaction for pool: ", pool["vault"])

        vault_address = pool["vault"]
        reward_distributor_address = pool["rewardDistributor"]
        vault_contract = get_contract(w3, vault_address, vault_abi)
        reward_distributor_contract = get_contract(w3, reward_distributor_address, reward_distributor_abi)

        data = vault_contract.functions.setCurveStrategy(STRATEGY).build_transaction({
            'from': GOVERNANCE,
        })['data']

        transactions.append({
            "to": vault_address,
            "value": 0,
            "data": data
        })

        data = reward_distributor_contract.functions.set_reward_distributor(CRV, STRATEGY).build_transaction({
            'from': GOVERNANCE,
        })['data']

        transactions.append({
            "to": reward_distributor_address,
            "value": 0,
            "data": data
        })

    # Create batches and save to JSON
    for idx, batch_transactions in enumerate(create_batches(transactions), start=1):
        batch_template['transactions'] = batch_transactions
        with open(f"script/batchs/batch_set_strategy_{idx}.json", 'w') as f:
            json.dump(batch_template, f, indent=4)

if __name__ == "__main__":
    main()
