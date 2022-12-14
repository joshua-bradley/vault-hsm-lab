#!/usr/bin/env bash

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
readonly __DEBUG="${MP_DEBUG:=0}"

# Define field seperator for word spllitting
# IFS=$' \n\t'

# set debug output
if [[ ${__DEBUG} = 1 || ${__DEBUG} = "TRUE" ]]; then
	set -o xtrace #Turn on traces, useful while debugging but unset by default
fi

# constants and environment
declare -xr VAULT_ADDR="http://127.0.0.1:8200"

vault operator init -key-shares=1 -key-threshold=1 -format=json >~/vault_init.json
vault operator unseal "$(jq -r .unseal_keys_b64[0] <~/vault_init.json)"
sleep 10 # wait for priamry node to become active
vault login "$(jq -r .root_token <~/vault_init.json)"
