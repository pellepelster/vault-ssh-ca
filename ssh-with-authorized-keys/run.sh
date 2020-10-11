#!/usr/bin/env bash

ssh-keygen -q -N "" -t rsa -b 4096 -f /ssh/ssh_host_rsa_key
/usr/sbin/sshd -D -f /ssh/sshd_config