#!/bin/bash

source .env

SUFFIX_COMMAND="--rpc-url ${RPC_URL} --broadcast -vv"

forge script DeployACPCCS $SUFFIX_COMMAND | grep LOG