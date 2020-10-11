#!/usr/bin/env bash

ssh-keygen -q -N "" -t rsa -b 4096 -f /ssh/ssh_host_rsa_key

# snippet:sign_host_key
curl --silent \
    --header "X-Vault-Token: root-token" \
    --request POST \
    --data "{ \"cert_type\": \"host\", \"public_key\": \"$(cat /ssh/ssh_host_rsa_key.pub)\" }" \
    http://vault:8200/v1/host-ssh/sign/host-ssh | jq -r .data.signed_key > /ssh/ssh_host_rsa_key_signed.pub
# /snippet:sign_host_key

# snippet:sign_host_key_permissions
chmod 0640 /ssh/ssh_host_rsa_key_signed.pub
# /snippet:sign_host_key_permissions

/usr/sbin/sshd -D -f /ssh/sshd_config