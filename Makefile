# Configuration
VERIFIER ?= etherscan
VERIFIER_URL ?= 
WITH_STORAGE ?= true
SIMULATED ?=
KEYSTORE_PATH ?= keystore/dcap_prod
PRIVATE_KEY ?=

# Required environment variables check
check_env:
ifdef RPC_URL
	$(eval CHAIN_ID := $(shell cast chain-id --rpc-url $(RPC_URL)))
	@echo "Chain ID: $(CHAIN_ID)"
else 
	$(error RPC_URL is not set)
endif

# Get the Owner's Wallet Address
get_owner:
ifdef PRIVATE_KEY
	$(eval OWNER := $(shell cast wallet address --private-key $(PRIVATE_KEY)))
else
	$(eval KEYSTORE_PASSWORD := $(shell read -s -p "Enter keystore password: " pwd; echo $$pwd))
	$(eval OWNER := $(shell cast wallet address --keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD) \
		|| (echo "Improper wallet configuration"; exit 1)))
endif
	@echo "\nWallet Owner: $(OWNER)"

# Deployment targets
deploy-helpers: check_env get_owner
	@echo "Deploying helper contracts..."
	@OWNER=$(OWNER) \
		forge script script/helper/DeployHelpers.s.sol:DeployHelpers \
		--rpc-url $(RPC_URL) \
		$(if $(PRIVATE_KEY), --private-key $(PRIVATE_KEY), \
		--keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD)) \
		$(if $(SIMULATED),, --broadcast) \
		$(if $(LEGACY), --legacy) \
		-vv
	@echo "Helper contracts deployed"

deploy-dao: check_env get_owner
	@echo "Deploying DAO contracts..."
	@if [ ! -f deployment/$(CHAIN_ID).json ]; then \
		echo "Helper addresses not found. Run deploy-helpers first"; \
		exit 1; \
	fi
	@OWNER=$(OWNER) \
		forge script script/automata/DeployAutomataDao.s.sol:DeployAutomataDao \
		--rpc-url $(RPC_URL) \
		$(if $(PRIVATE_KEY), --private-key $(PRIVATE_KEY), \
		--keystore $(KEYSTORE_PATH) --password $(KEYSTORE_PASSWORD)) \
		$(if $(SIMULATED),, --broadcast) \
		$(if $(LEGACY), --legacy) \
		-vv \
		--sig "deployAll(bool)" $(WITH_STORAGE)
	@echo "DAO contracts deployed"

deploy-all: deploy-helpers deploy-dao
	@echo "Deployment completed"

# Contract verification
verify-helpers: check_env
	@echo "Verifying helper contracts..."
	@if [ ! -f deployment/$(CHAIN_ID).json ]; then \
		echo "Helper addresses not found. Deploy helpers first."; \
		exit 1; \
	fi
	@for contract in EnclaveIdentityHelper FmspcTcbHelper PCKHelper X509CRLHelper; do \
		addr=$$(jq -r ".$$contract" deployment/$(CHAIN_ID).json); \
		if [ "$$addr" != "null" ]; then \
			forge verify-contract \
				--rpc-url $(RPC_URL) \
				--verifier $(VERIFIER) \
				--watch \
				$(if $(VERIFIER_URL),--verifier-url $(VERIFIER_URL)) \
				$$addr \
				src/helpers/$$contract.sol:$$contract || true; \
		fi \
	done

verify-dao: check_env get_owner
	@echo "Verifying DAO contracts..."
	@if [ ! -f deployment/$(CHAIN_ID).json ]; then \
		echo "DAO addresses not found. Deploy DAOs first."; \
		exit 1; \
	fi
	@echo "Determining P256 Verifier address..."
	@P256_ADDRESS_VAL=$$(forge script script/utils/P256Configuration.sol:P256Configuration --rpc-url $(RPC_URL) --sig "simulateVerify()" -vv | awk '/P256Verifier address:/ { print $$NF; exit }'); \
	echo "Using P256 Verifier address: $$P256_ADDRESS_VAL"; \
	STORAGE_ADDR=$$(jq -r ".AutomataDaoStorage" deployment/$(CHAIN_ID).json); \
	X509_HELPER_ADDR=$$(jq -r ".PCKHelper" deployment/$(CHAIN_ID).json); \
	CRL_HELPER_ADDR=$$(jq -r ".X509CRLHelper" deployment/$(CHAIN_ID).json); \
	PCS_DAO_ADDR=$$(jq -r ".AutomataPcsDao" deployment/$(CHAIN_ID).json); \
	ENCLAVE_IDENTITY_HELPER_ADDR=$$(jq -r ".EnclaveIdentityHelper" deployment/$(CHAIN_ID).json); \
	FMSPC_TCB_HELPER_ADDR=$$(jq -r ".FmspcTcbHelper" deployment/$(CHAIN_ID).json); \
	for contract_name_loop in AutomataDaoStorage AutomataPcsDao AutomataPckDao AutomataEnclaveIdentityDao AutomataFmspcTcbDao; do \
		contract_addr=$$(jq -r ".$$contract_name_loop" deployment/$(CHAIN_ID).json); \
		current_encoded_args=""; \
		current_contract_path_name=""; \
		if [ "$$contract_addr" != "null" ]; then \
			echo "Preparing to verify $$contract_name_loop at $$contract_addr..."; \
			if [ "$$contract_name_loop" = "AutomataDaoStorage" ]; then \
				current_encoded_args=$$(cast abi-encode "constructor(address)" $(OWNER)); \
				current_contract_path_name="src/automata_pccs/shared/AutomataDaoStorage.sol:AutomataDaoStorage"; \
			elif [ "$$contract_name_loop" = "AutomataPcsDao" ]; then \
				current_encoded_args=$$(cast abi-encode "constructor(address,address,address,address)" $$STORAGE_ADDR $$P256_ADDRESS_VAL $$X509_HELPER_ADDR $$CRL_HELPER_ADDR); \
				current_contract_path_name="src/automata_pccs/AutomataPcsDao.sol:AutomataPcsDao"; \
			elif [ "$$contract_name_loop" = "AutomataPckDao" ]; then \
				current_encoded_args=$$(cast abi-encode "constructor(address,address,address,address,address)" $$STORAGE_ADDR $$P256_ADDRESS_VAL $$PCS_DAO_ADDR $$X509_HELPER_ADDR $$CRL_HELPER_ADDR); \
				current_contract_path_name="src/automata_pccs/AutomataPckDao.sol:AutomataPckDao"; \
			elif [ "$$contract_name_loop" = "AutomataEnclaveIdentityDao" ]; then \
				current_encoded_args=$$(cast abi-encode "constructor(address,address,address,address,address,address)" $$STORAGE_ADDR $$P256_ADDRESS_VAL $$PCS_DAO_ADDR $$ENCLAVE_IDENTITY_HELPER_ADDR $$X509_HELPER_ADDR $$CRL_HELPER_ADDR); \
				current_contract_path_name="src/automata_pccs/AutomataEnclaveIdentityDao.sol:AutomataEnclaveIdentityDao"; \
			elif [ "$$contract_name_loop" = "AutomataFmspcTcbDao" ]; then \
				current_encoded_args=$$(cast abi-encode "constructor(address,address,address,address,address,address)" $$STORAGE_ADDR $$P256_ADDRESS_VAL $$PCS_DAO_ADDR $$FMSPC_TCB_HELPER_ADDR $$X509_HELPER_ADDR $$CRL_HELPER_ADDR); \
				current_contract_path_name="src/automata_pccs/AutomataFmspcTcbDao.sol:AutomataFmspcTcbDao"; \
			fi; \
			echo "Verifying $$contract_name_loop with encoded args: $$current_encoded_args"; \
			forge verify-contract \
				--rpc-url $(RPC_URL) \
				--verifier $(VERIFIER) \
				--watch \
				$(if $(VERIFIER_URL),--verifier-url $(VERIFIER_URL)) \
				$$contract_addr \
				$$current_contract_path_name \
				--constructor-args $$current_encoded_args || true; \
		fi; \
	done

verify-all: verify-helpers verify-dao
	@echo "Verification completed"

# Utility targets
clean:
	forge clean

# Help target
help:
	@echo "Available targets:"
	@echo "  deploy-helpers      Deploy helper contracts"
	@echo "  deploy-dao          Deploy DAO contracts"
	@echo "  deploy-all          Deploy all contracts"
	@echo "  verify-helpers      Verify helper contracts"
	@echo "  verify-dao          Verify DAO contracts"
	@echo "  verify-all          Verify all contracts"
	@echo "  clean               Remove build artifacts"
	@echo ""
	@echo "Wallet environment variables: (you only need to set one)"
	@echo "  PRIVATE_KEY         Private key for wallet"
	@echo "  KEYSTORE_PATH       Path to keystore directory"
	@echo ""
	@echo "Required environment variables:"
	@echo "  RPC_URL             RPC URL for the target network"
	@echo ""
	@echo "Optional environment variables:"
	@echo "  VERIFIER            Contract verifier (default: etherscan)"
	@echo "  VERIFIER_URL        Custom verifier API URL"
	@echo "  ETHERSCAN_API_KEY   API key for contract verification"
	@echo "  WITH_STORAGE        Deploy with storage (default: true)"
	@echo "  SIMULATED           Simulate deployment (default: false)"
	@echo ""
	@echo "Example usage:"
	@echo "  make deploy-all RPC_URL=xxx"
	@echo "  make verify-all RPC_URL=xxx ETHERSCAN_API_KEY=xxx"
	@echo "  make deploy-dao PRIVATE_KEY=xxx RPC_URL=xxx SIMULATED=true"

.PHONY: check_env clean help deploy-% verify-%
