.PHONY: all test clean deploy fund withdraw help install snapshot format anvil

# Load environment variables from .env file
include .env
export $(shell sed 's/=.*//' .env)

help:
	@echo "usage:"
	@echo "  make              => build & test everything"
	@echo "  make anvil        => start local anvil chain"
	@echo "  make test         => run all tests"
	@echo "  make clean        => clean build artifacts"
	@echo "  make deploy       => deploy FundMe"
	@echo "  make fund         => fund deployed FundMe"
	@echo "  make withdraw     => withdraw funds"
	@echo "  make install      => install dependencies"
	@echo "  make snapshot     => run gas snapshot"
	@echo "  make format       => format code"

all: test

anvil:
	anvil -s $(DEFAULT_ANVIL_KEY)

test:
	forge test -vvv

clean:
	forge clean

deploy:
	forge script script/DeployFundMe.s.sol:DeployFundMe \
		--rpc-url $(SEPOLIA_RPC_URL) \
		--private-key $(PRIVATE_KEY) \
		--broadcast \
		--verify \
		--etherscan-api-key $(ETHERSCAN_API_KEY)

fund:
	cast send --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) \
		--to $(CONTRACT_ADDRESS) --value $(ETH_VALUE)

withdraw:
	cast send --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) \
		--to $(CONTRACT_ADDRESS) "withdraw()"

install:
	forge install smartcontractkit/chainlink-brownie-contracts --no-commit

snapshot:
	forge snapshot

format:
	forge fmt
