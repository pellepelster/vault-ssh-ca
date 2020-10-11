#!/usr/bin/env bash

set -eux

ssh-keygen -q -N "" -t rsa -b 4096 -f /ssh/ssh_host_rsa_key

# snippet:download_user_ssh_public_key
curl --silent http://vault:8200/v1/user-ssh/public_key > /ssh/user_ssh_ca.pub
chmod 0640 /ssh/user_ssh_ca.pub
# /snippet:download_user_ssh_public_key

curl --silent \
    --header "X-Vault-Token: root-token" \
    --request POST \
    --data "{ \"cert_type\": \"host\", \"public_key\": \"$(cat /ssh/ssh_host_rsa_key.pub)\" }" \
    http://vault:8200/v1/host-ssh/sign/host-ssh | jq -r .data.signed_key > /ssh/ssh_host_rsa_key_signed.pub
chmod 0640 /ssh/ssh_host_rsa_key_signed.pub

/usr/sbin/sshd -e -D -f /ssh/sshd_config