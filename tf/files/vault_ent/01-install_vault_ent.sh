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

# echo "Running updates and installing unzip, jq"
sudo apt update -y
sudo apt install unzip jq -y

echo "Installing Vault Enterprise"
# Setup vault enterprise as server
# USER VARS
VAULT_VERSION="1.9.3"
NODE_NAME="${1:-$(hostname -s)}"
VAULT_DIR=/usr/local/bin
VAULT_CONFIG_DIR=/etc/vault.d
VAULT_DATA_DIR=/opt/vault

# CALCULATED VARS
VAULT_PATH=${VAULT_DIR}/vault
VAULT_ZIP="vault_${VAULT_VERSION}+ent_linux_amd64.zip"
VAULT_URL="https://releases.hashicorp.com/vault/${VAULT_VERSION}+ent/${VAULT_ZIP}"

# CHECK DEPENDANCIES AND SET NET RETRIEVAL TOOL
if ! unzip -h 2 &>/dev/null; then
  echo "aborting - unzip not installed and required"
  exit 1
fi
if curl -h 2 &>/dev/null; then
  nettool="curl"
elif wget -h 2 &>/dev/null; then
  nettool="wget"
else
  echo "aborting - neither wget nor curl installed and required"
  exit 1
fi

set +e

# try to get private IP
pri_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
set -e

# download and extract binary
echo "Downloading and installing vault ${VAULT_VERSION}"
case "${nettool}" in
wget)
  wget --no-check-certificate "${VAULT_URL}" --output-document="${VAULT_ZIP}"
  ;;
curl)
  [ 200 -ne "$(curl --write-out "%{http_code}" --silent --output ${VAULT_ZIP} ${VAULT_URL})" ] && exit 1
  ;;
esac

unzip "${VAULT_ZIP}"
sudo mv vault "$VAULT_DIR"
sudo chmod 0755 "${VAULT_PATH}"
sudo chown root:root "${VAULT_PATH}"

echo "Version Installed: $(vault --version)"
vault -autocomplete-install
complete -C "${VAULT_PATH}" vault
sudo setcap cap_ipc_lock=+ep "${VAULT_PATH}"

echo "Creating Vault user and directories"
sudo mkdir --parents "${VAULT_CONFIG_DIR}"
sudo useradd --system --home "${VAULT_CONFIG_DIR}" --shell /bin/false vault
sudo mkdir --parents "${VAULT_DATA_DIR}"
sudo chown --recursive vault:vault "${VAULT_DATA_DIR}"

echo "Creating vault config for ${VAULT_VERSION}"
sudo tee "${VAULT_CONFIG_DIR}/vault.hcl" >/dev/null <<VAULTCONFIG
ui = true
api_addr = ""
cluster_addr = ""
cluster_name="vault-enterprise"

listener "tcp" {
  address          = "0.0.0.0:8200"
  tls_disable      = "true"
}

# Integrated Storage Backend
storage "raft" {
  path    = "/opt/vault"
  node_id = "vault-1"
}

# Enterprise License Auto-Load
license_path = "/home/ubuntu/vault.hclic"
VAULTCONFIG

sudo sed -i "s|NODENAME|$NODE_NAME|g" "${VAULT_CONFIG_DIR}/vault.hcl"
[[ "$pri_ip" ]] && sudo sed -i "s|^api_addr.*|api_addr = \"http://$pri_ip:8200\"|g" "${VAULT_CONFIG_DIR}/vault.hcl"
[[ "$pri_ip" ]] && sudo sed -i "s|^cluster_addr.*|cluster_addr = \"https://$pri_ip:8201\"|g" "${VAULT_CONFIG_DIR}/vault.hcl"
[[ "$pri_ip" ]] && sudo sed -i "s|^#\ \ cluster_address.*|\ \ cluster_address  = \"$pri_ip:8201\"|g" "${VAULT_CONFIG_DIR}/vault.hcl"
sudo chown --recursive vault:vault "${VAULT_CONFIG_DIR}"
sudo chmod 640 "${VAULT_CONFIG_DIR}/vault.hcl"

echo "Creating vault systemd service"
sudo tee /etc/systemd/system/vault.service >/dev/null <<'SYSDSERVICE'
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=VAULTBINDIR/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP ${MAINPID}
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitIntervalSec=60
StartLimitBurst=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SYSDSERVICE

sudo sed -i "s|VAULTBINDIR|$VAULT_DIR|g" /etc/systemd/system/vault.service

echo 'export VAULT_ADDR="http://127.0.0.1:8200"' >>~/.bashrc

# shellcheck source=/dev/null
# source "${HOME}"/.bashrc

echo "Enable Vault systemd service"
sudo systemctl enable vault
sudo systemctl start vault
sudo systemctl status vault
