-include .env

.EXPORT_ALL_VARIABLES:
FOUNDRY_ETH_RPC_URL=$(RPC_URL_MAINNET)
ETHERSCAN_API_KEY=$(ETHERSCAN_KEY)
MAKEFLAGS += --no-print-directory

default:
	forge fmt && forge build

# Always keep Forge up to date
install:
	foundryup
	forge install

test:
	forge test --gas-report #--match-contract _188_Deposit_Test

test-%:
	@FOUNDRY_TEST=test/$* make test

snapshot:
	forge snapshot

test-f-%:
	@FOUNDRY_MATCH_TEST=test/$* make test 

test-c-%:
	@FOUNDRY_MATCH_CONTRACT=test/$* make test

coverage:
	forge coverage --match-path

coverage-lcov:
	forge coverage --report lcov
	lcov --remove ./lcov.info -o ./lcov.info.pruned

coverage-html:
	make coverage
	genhtml ./lcov.info.pruned -o report --branch-coverage --output-dir ./coverage
	rm ./lcov.info*


.PHONY: test coverage
