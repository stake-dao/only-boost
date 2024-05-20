import json, os, requests, re
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


def get_info(address):
    base_url = "https://api.etherscan.io/api"
    params = {
        "module": "contract",
        "action": "getsourcecode",
        "address": address,
        "apikey": os.getenv("ETHERSCAN_KEY"),
    }

    response = requests.get(base_url, params=params)
    if response.status_code == 200:
        name = response.json()["result"][0]["ContractName"]
        compiler_version = response.json()["result"][0]["CompilerVersion"]

        source_code = response.json()["result"][0]["SourceCode"]

        # Define the regular expression pattern
        pattern = r"@title\s+(.+)"
        # Search the pattern in the source code
        match = re.search(pattern, source_code)

        if len(match.group(1)) > 0:
            name = match.group(1).strip()

        return {"name": name, "compiler_version": compiler_version, "example_impl": address, "source_code": source_code, "implementation": 1}
    else:
        return {None, None}
    

# Function to add or update the type
def add_or_update_type(types, new_type):
    for existing_type in types:
        if existing_type["name"] == new_type["name"] and existing_type["compiler_version"] == new_type["compiler_version"] and existing_type["source_code"] == new_type["source_code"]:
            existing_type["implementation"] += 1
            break
    else:
        print("Adding type", new_type["name"], new_type["compiler_version"], new_type["example_impl"])
        types.append(new_type)


def main():
    w3 = initialize_web3()

    controller_abi = load_abi("test/external/controller.json")

    CONTROLLER = "0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB"
    controller = get_contract(w3, CONTROLLER, controller_abi)

    pool_length = controller.functions.n_gauges().call()

    types = []

    for i in range(pool_length):
        gauge = controller.functions.gauges(i).call()
        type = get_info(gauge)
        add_or_update_type(types, type)

    # Create a new list with the specified key excluded from each dictionary
    filtered_types = [{k: v for k, v in type_dict.items() if k != "source_code"} for type_dict in types]

    # Sort by the number of implementations
    filtered_types = sorted(filtered_types, key=lambda x: x["implementation"], reverse=True)
    
    # Dump the types to a file
    with open("types.json", "w") as f:
        json.dump(filtered_types, f, indent=4)
    


    print("Number of types:", len(types))


if __name__ == "__main__":
    main()
