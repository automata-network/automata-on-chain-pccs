#!/bin/bash

source .env

SUFFIX_COMMAND="--rpc-url ${RPC_URL} --broadcast -vv"

forge script DeployHelpers --sig "deployEnclaveIdentityHelper()" $SUFFIX_COMMAND | grep LOG
forge script DeployHelpers --sig "deployFmspcTcbHelper()" $SUFFIX_COMMAND | grep LOG
forge script DeployHelpers --sig "deployPckHelper()" $SUFFIX_COMMAND | grep LOG
forge script DeployHelpers --sig "deployX509CrlHelper()" $SUFFIX_COMMAND | grep LOG

echo "Don't forget to provide the new addresses to .env!"