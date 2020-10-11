#!/usr/bin/env bash

set -eu

DIR="$(cd "$(dirname "$0")" ; pwd -P)"
source "${DIR}/ctuhl/lib/shell/common.sh"

SNIPPETS_TEMP_DIR="${DIR}/.snippets"

function task_clean {
  rm -rf "${DIR}/ssh-keys"
  rm -rf "${DIR}/ssh-with-signed-hostkey/ssh-keys"
  rm -rf "${DIR}/ssh-with-authorized-keys/ssh-keys"

  docker-compose rm -sf 
}

function ensure_software {
  ensure_terraform "${DIR}/.bin"
}

function task_start_vault {
  docker-compose up -d vault
}

function task_start_ssh_with_authorized_keys {
  docker-compose up -d ssh-with-authorized-keys
}

function task_start_ssh_with_signed_hostkey {
  docker-compose up -d ssh-with-signed-hostkey
}

function task_stop_ssh_with_signed_hostkey {
  docker-compose rm -sf ssh-with-authorized-keys
}

function task_start_ssh_with_trusted_user_ca {
  docker-compose up -d ssh-with-trusted-user-ca
}

function task_stop_ssh_with_trusted_user_ca {
  docker-compose rm -sf ssh-with-trusted-user-ca
}

function task_terraform_apply_ssh_with_signed_hostkey {
  task_terraform "ssh-with-signed-hostkey" "init" 
  task_terraform "ssh-with-signed-hostkey" "apply" "$@"
}

function task_terraform_apply_ssh_with_trusted_user_ca {
  task_terraform "ssh-with-trusted-user-ca" "init"
  task_terraform "ssh-with-trusted-user-ca" "apply" "$@"
}

function task_terraform {
  export VAULT_ADDR=http://localhost:8200
  export VAULT_TOKEN=root-token
  local tf_dir=${1:-}
  shift || true
  (
    cd "${tf_dir}"
    "${DIR}/.bin/terraform" "$@"
  )
}

function task_prepare {
  task_clean
  ensure_software
  mkdir -p "${DIR}/ssh-keys"
  ssh-keygen -b 2048 -t rsa -f "${DIR}/ssh-keys/bob_id_rsa" -q -N ""
  ssh-keygen -b 2048 -t rsa -f "${DIR}/ssh-keys/alice_id_rsa" -q -N ""

  mkdir -p "${DIR}/ssh-with-signed-hostkey/ssh-keys"
  cp "${DIR}/ssh-keys/bob_id_rsa.pub" "${DIR}/ssh-with-signed-hostkey/ssh-keys"

  mkdir -p "${DIR}/ssh-with-authorized-keys/ssh-keys"
  cp "${DIR}/ssh-keys/bob_id_rsa.pub" "${DIR}/ssh-with-authorized-keys/ssh-keys"

  docker-compose -f "${DIR}/docker-compose.yml" build
}

function task_generate_and_insert_snippets() {

  rm -rf "${SNIPPETS_TEMP_DIR}"
  mkdir -p "${SNIPPETS_TEMP_DIR}" || true 

  echo "generating snippets for '${DIR}'"
  (
    for file in $(git ls-tree -r master --name-only .); do
      if [[ $file != *.md ]]; then
        GITHUB_REPOSITORY="pellepelster/ctuhl" SNIPPETS_TEMP_DIR="${SNIPPETS_TEMP_DIR}" REPOSITORY_FILE_PREFIX="vault" bundle exec ruby "${DIR}/../lib/ruby/extract_snippets.rb" "${file}"
      fi
    done
  )
  
  local file="${DIR}/POST.md"
  echo "inserting snippets for '${file}'"
  (
    GITHUB_REPOSITORY="pellepelster/ctuhl" SNIPPETS_TEMP_DIR="${SNIPPETS_TEMP_DIR}" REPOSITORY_FILE_PREFIX="vault" FILES_DIR="${DIR}" bundle exec ruby "${DIR}/../lib/ruby/insert_snippets.rb" "${file}"
  )

}

function task_create_host_signing_key {
  # snippet:create_host_signing_key
  curl \
    --header "X-Vault-Token: root-token" \
    --request POST \
    --data '{"generate_signing_key": true}' \
    http://localhost:8200/v1/host-ssh/config/ca 
  # /snippet:create_host_signing_key
}

function task_create_user_signing_key {
  # snippet:create_user_signing_key
  curl \
    --header "X-Vault-Token: root-token" \
    --request POST \
    --data '{"generate_signing_key": true}' \
    http://localhost:8200/v1/user-ssh/config/ca 
  # /snippet:create_user_signing_key
}

function task_create_known_hosts {
  # snippet:create_known_hosts
  echo "@cert-authority localhost $(curl --silent --header "X-Vault-Token: root-token" http://localhost:8200/v1/host-ssh/public_key)" > "known_hosts"
  # /snippet:create_known_hosts
}

function task_ssh_with_signed_hostkey {
  ssh -o UserKnownHostsFile=./known_hosts  -p 2022 -i ssh-keys/bob_id_rsa admin-ssh-user@localhost
}

function task_ssh_with_trusted_user_ca {
  ssh -o UserKnownHostsFile=./known_hosts  -p 3022 -i ssh-keys/alice_id_rsa_signed.pub -i ssh-keys/alice_id_rsa admin-ssh-user@localhost
}

function task_sign_alice_key {
  # snippet:sign_alice_key
  curl --silent \
    --header "X-Vault-Token: root-token" \
    --request POST \
    --data "{\"public_key\":\"$(cat ssh-keys/alice_id_rsa.pub)\"}" \
    http://localhost:8200/v1/user-ssh/sign/user-ssh | jq -r .data.signed_key > ssh-keys/alice_id_rsa_signed.pub
  # /snippet:sign_alice_key
}

function task_test {
  task_clean
  task_prepare
  task_start_vault
  task_terraform_apply_ssh_with_signed_hostkey "-auto-approve"
  task_terraform_apply_ssh_with_trusted_user_ca "-auto-approve"
  task_create_host_signing_key
  task_create_user_signing_key
  task_create_known_hosts
  task_sign_alice_key
  task_start_ssh_with_authorized_keys
  task_start_ssh_with_signed_hostkey
  task_start_ssh_with_trusted_user_ca
}

function task_usage {
  echo "Usage: $0 ..."
  exit 1
}

arg=${1:-}
shift || true
case ${arg} in
  clean) task_clean "$@" ;;
  prepare) task_prepare "$@" ;;
  start-vault) task_start_vault ;;
  start-ssh-with-authorized-keys) task_start_ssh_with_authorized_keys ;;
  start-ssh-with-signed-hostkey) task_start_ssh_with_signed_hostkey ;;
  stop-ssh-with-authorized-keys) task_stop_ssh_with_signed_hostkey ;;
  start-ssh-with-trusted-user-ca) task_start_ssh_with_trusted_user_ca ;;
  stop-ssh-with-trusted-user-ca) task_stop_ssh_with_trusted_user_ca ;;
  terraform-apply-ssh-with-signed-hostkey) task_terraform_apply_ssh_with_signed_hostkey "$@" ;;
  terraform-apply-ssh-with-trusted-user-ca) task_terraform_apply_ssh_with_trusted_user_ca "$@" ;;
  create-host-signing-key) task_create_host_signing_key ;;
  create-user-signing-key) task_create_user_signing_key ;;
  create-known-hosts) task_create_known_hosts ;;
  ssh-with-signed-hostkey) task_ssh_with_signed_hostkey ;;
  generate-and-insert-snippets) task_generate_and_insert_snippets ;;
  test) task_test ;;
  *) task_usage ;;
esac