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
	forge test

test-%:
	@FOUNDRY_TEST=test/$* make test

snapshot:
	forge snapshot

test-f-%:
	@FOUNDRY_MATCH_TEST=$* make test 

test-c-%:
	@FOUNDRY_MATCH_CONTRACT=$* make test

coverage:
	forge coverage --match-path 'test/integration/*'

coverage-lcov:
	forge coverage --report lcov
	lcov --remove ./lcov.info -o ./lcov.info.pruned 'test/integration/*'

coverage-html:
	make coverage
	genhtml ./lcov.info.pruned -o report --branch-coverage --output-dir ./coverage
	rm ./lcov.info*


.PHONY: test coverage
