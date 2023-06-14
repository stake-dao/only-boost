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
	@FOUNDRY_MATCH_TEST=$* make test

coverage:
	forge coverage --report lcov
	lcov --remove lcov.info -o lcov.info "test/*"

coverage-html:
	make coverage
	@echo Transforming the lcov coverage report into html
	genhtml lcov.info -o coverage

.PHONY: test coverage