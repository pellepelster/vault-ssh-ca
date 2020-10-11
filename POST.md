---
title: "CA secured SSH connections"
date: 2020-03-22T20:00:00+01:00
draft: false
---

This post will show you how to use vault, signed SSH keys and some bash glue code to secure SSH connections, make them more verifiable and allow flexible access to your SSH servers.

<!--more-->

# Preface

This tutorial assume that you are already familiar with basic bash programming and the involved tools namely terraform, vault and SSH.

All needed sources for this tutorial are availabe at [https://github.com/pellepelster/ctuhl.git](https://github.com/pellepelster/ctuhl.git) inside the folder `vault`.

```
git clone https://github.com/pellepelster/ctuhl.git
cd vault
```

To be able to follow all examples you have to build some prerequisites first, which can be simply done by calling

```
./do prepare
```

Also there are helper tasks to execute all the needed tooling and to start/stop needed containers, so we can fully focus on the functionality and do not have to fiddle around with tooling issues. If you get stuck you can call `./do clean` at any time to reset everything to its initial state. 

Commands that you can execute are show like this

```
./do some-command
```

Configuration files and scripts are displayed this way

{{< highlight go "" >}}
#!/usr/bin/env bash

echo "Hello World!"
{{< / highlight >}}


# The problem

Before we start lets have a look at a typical SSH setup you would encounter in the wild at any common cloud provider. Typically before you spin up the first VM, you will have to upload your SSH public key to your cloud provider of choice. On VM start your provider will then provision a  `~/.ssh/authorized_keys` file via [cloud-init](https://cloudinit.readthedocs.io/en/latest/) allowing you to login from your local machine with your provided SSH key when a new host is VM. 

To make it easier to replicate this setup locally we will use docker containers as stand-in doubles for real cloud VMs. To mimic the on-boot behavior of cloud init the docker containers are configured to re-generate it's SSH host keys on start in its `/ssh/run.sh` script. 

So lets start a docker container that contains an plain SSH server with the follwing simple SSH daemon configuration

<!-- file:ssh-with-authorized-keys/sshd_config -->

{{< github repository="pellepelster/vault-ssh-ca" file="ssh-with-authorized-keys/sshd_config"  >}}ssh-with-authorized-keys/sshd_config{{< /github >}}

{{< highlight go "" >}}
Port 22
UsePAM yes
HostKey /ssh/ssh_host_rsa_key

AuthorizedKeysFile %h/.ssh/authorized_keys

{{< / highlight >}}
<!-- /file:ssh-with-authorized-keys/sshd_config -->

you can start the container by running

```
./do start-ssh-with-authorized-keys
```

As during the docker build of this container we baked in the previously generated SSH key of Bob and added it to the `~/authorized_keys` of the `admin-ssh-user´, we can log into this container by


```
ssh -p 1022 -i ssh-keys/bob_id_rsa admin-ssh-user@localhost
```

The first thing we notice is that on first connect, we have to verify the identity of the SSH server which is typically done by verifying the cryptographic fingerprints

```
The authenticity of host '[localhost]:1022 ([::1]:1022)' can't be established.
ECDSA key fingerprint is SHA256:c99kZespMBlc4yBnz0owUXb85l/hmuqBrpIc4rY0qOU.
Are you sure you want to continue connecting (yes/no)? 
```

We normally happily accept the connection (after of course manually verifying the identity), and go on with what we wanted to do via SSH.

But lets step back for a small bit and contemplate what just happened: We tried to establish a secure connection to a remote server. To establish that this is really the server we wanted to connect to in the frist place (and not some man-in-the-middle attack) we had to manually verify the servers identity. Imagine you would have to do this every time you connect to a new website. This certainly is an approach that may work for a small numbers of machines but does definitly not scale very well with larger setups.

The even bigger problem starts when a new instance of a VM is started. As the identity of the SSH server is generated when the SSH server is configured and in a cloud environment this is done on every machine boot, the next time you start a new server a new identity is generated and thus the servers fingerprint changes.
We can emulate this by restarting the docker container

```
./do stop-ssh-with-authorized-keys
./do start-ssh-with-authorized-keys
```

and try to login again

```
ssh -p 1022 -i ssh-keys/bob_rsa admin-ssh-user@localhost
```

now we get an ugly warning, because we told our local SSH client to trust the server at `localhost:1022`  with the fingerprint `SHA256:c99kZespMBlc4yBnz0owUXb85l/hmuqBrpIc4rY0qOU` but the fingerprint changed to `SHA256:6amS+onNlSlFK/0cw6IvS+EJ4rqAzlc1YTZLGuZTr2Y`.


```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
Someone could be eavesdropping on you right now (man-in-the-middle attack)!
It is also possible that a host key has just been changed.
The fingerprint for the ECDSA key sent by the remote host is
SHA256:6amS+onNlSlFK/0cw6IvS+EJ4rqAzlc1YTZLGuZTr2Y.
Please contact your system administrator.
Add correct host key in /home/pelle/.ssh/known_hosts to get rid of this message.
Offending ECDSA key in /home/pelle/.ssh/known_hosts:43
  remove with:
  ssh-keygen -f "/home/pelle/.ssh/known_hosts" -R "[localhost]:1022"
ECDSA host key for [localhost]:1022 has changed and you have requested strict checking.
Host key verification failed.
```

The next problem becomes obvious when we need to allow a new user to access the `admin-ssh-user` of our machine. Because the setup relies on the fact that the users public key is previously known to the machines, we would need to add the ssh public key of the new user to all machines `~/authorized_keys` files.
So in order to allow Alice to login as well via

```
ssh -p 1022 -i ssh-keys/alice_id_rsa admin-ssh-user@localhost
```

We would need to re-provision of all machines with the new SSH keys.

These two problems both boil down to a missing [trust anchor](https://en.wikipedia.org/wiki/Trust_anchor) for both sides of the SSH connection.

When we connect to an SSH server it would be nice if we could verify that the servers identity was created by someone we trust. Vice versa if the SSH server would be able to verify that the SSH key was issued by someone he trusts we could easily add more users without needing to re-provision all servers.

This is in essence the same problem that web browsers have. Users can not manually verify the certificates of all sites they access (nor can they for SSH). Instead each browser has a list of certificate authorities (CAs) it trusts. Websites offering SSL then send the public keys of certificates that were issued and signed by those CAs (or its descendants) and the browser is able to verify a websites authenticity by verifying the whole [certificate chain](https://en.wikipedia.org/wiki/Chain_of_trust) up to its ultimate root which are the CAs that are stored in the browsers or operating system trust store.

We can leverage this mechanism for SSH connections as well, and establish trust to individual SSH servers by using CAs that act as a trust anchor for our SSH connections. This post will explain how to do this, using the SSH CA functionality of HashiCorp`s [vault](https://www.vaultproject.io).


# Introducing Vault

Beside its functionality as secret store vault has builtin capabilities to mange CAs for dealing with X509 certificates. More interestingly those CA facilities can also be used to create and sign keys that are used to encrypt SSH sessions.

## Creating trusted host keys

Lets first look at the direction from the SSH client to the host.  

To mimic the way a browser verifies a hosts authenticity we would need the public key of a CA locally, and this CA has to sign the SSH servers host key. By signing the host key, the signer indicates to any third party that the signer trusts the signee. This enables any party who trusts the signer to extend her trust to the signee as well.

We are gonna use a vault server in development mode, so we don't have to fiddle around with establishing a secure relation between the different parties using vault tokens. It is thou important to note that the relation between vault and all entities using vault is now an important part of our trust chain. If this chain can't be trusted, everything that is derived from it (like in the current example a signed host key) can't be trusted as well. For more information about vault tokens look [here](https://www.vaultproject.io/docs/concepts/tokens/).

First thing we have to do, is starting the vault server that will act as our CA and trust anchor

```
./do start-vault
```

Vault uses tokens for all authentication purposes. For this tutorial we use the static token `root-token` for all vault interactions. If you want to see vault in action, visit http://localhost:8200, and use this root token to log in.

Next step is to create a backend in vault that is able to act as a CA. In vault those backends are called secret engines, and multiple of the same type can be created for different purposes. To configure vault we are gonna use terraform

First create a secret engine that is able to handle [SSH secrets](https://www.vaultproject.io/docs/secrets/ssh/)

<!-- snippet:vault_mount_host_ssh -->

{{< github repository="pellepelster/vault-ssh-ca" file="ssh-with-signed-hostkey/main.tf#L2-L6"  >}}ssh-with-signed-hostkey/main.tf{{< /github >}}

{{< highlight go "" >}}
resource "vault_mount" "host_ssh" {
  path        = "host-ssh"
  type        = "ssh"
  description = "host-ssh"
}
{{< / highlight >}}
<!-- /snippet:vault_mount_host_ssh -->

next step is to create a role, specifing the exact details of the CA and how the keys should be signed 

<!-- snippet:vault_ssh_secret_backend_role_host_ssh_role -->

{{< github repository="pellepelster/vault-ssh-ca" file="ssh-with-signed-hostkey/main.tf#L10-L16"  >}}ssh-with-signed-hostkey/main.tf{{< /github >}}

{{< highlight go "" >}}
resource "vault_ssh_secret_backend_role" "host_ssh_role" {
    name                    = "host-ssh"
    backend                 = vault_mount.host_ssh.path
    key_type                = "ca"
    allow_host_certificates = true
    allow_user_certificates = false
}
{{< / highlight >}}
<!-- /snippet:vault_ssh_secret_backend_role_host_ssh_role -->

we can then apply the configuration by running terraform against the running vault instance

```
./do terraform-apply-ssh-with-signed-hostkey
```

If we now look at the created SSH secret backend in the UI we notice that it seems to be missing an actual CA kepair which would be needed to actually sign other keys. Reason for this is we first have to generate a keypair (we could also import a key that was created outside of vault, but we go for the easy approach here)

<!-- snippet:create_host_signing_key -->

{{< github repository="pellepelster/vault-ssh-ca" file="do#L89-L93"  >}}do{{< /github >}}

{{< highlight go "" >}}
  curl \
    --header "X-Vault-Token: root-token" \
    --request POST \
    --data '{"generate_signing_key": true}' \
    http://localhost:8200/v1/host-ssh/config/ca 
{{< / highlight >}}
<!-- /snippet:create_host_signing_key -->

Now we are ready to go, we have a fully loaded and configured CA to sign our SSH host keys. We use the containers run script `/ssh/run.sh` to sign the new host key on each container start. First step is to sign the host key of our SSH server

<!-- snippet:sign_host_key -->

{{< github repository="pellepelster/vault-ssh-ca" file="ssh-with-signed-hostkey/run.sh#L6-L10"  >}}ssh-with-signed-hostkey/run.sh{{< /github >}}

{{< highlight go "" >}}
curl --silent \
    --header "X-Vault-Token: root-token" \
    --request POST \
    --data "{ \"cert_type\": \"host\", \"public_key\": \"$(cat /ssh/ssh_host_rsa_key.pub)\" }" \
    http://vault:8200/v1/host-ssh/sign/host-ssh | jq -r .data.signed_key > /ssh/ssh_host_rsa_key_signed.pub
{{< / highlight >}}
<!-- /snippet:sign_host_key -->

We post the key to sign via curl to the vault api and requesting a signed host key by `"cert_type": "host"`. The important part of the response, namely the signed host key is extracted via `jq` and written to a file.
The next step is important, because SSH is very picky about file permissions (for a good reason), but does not always tell us when if fails because of too open permissions

<!-- snippet:sign_host_key_permissions -->

{{< github repository="pellepelster/vault-ssh-ca" file="ssh-with-signed-hostkey/run.sh#L14-L14"  >}}ssh-with-signed-hostkey/run.sh{{< /github >}}

{{< highlight go "" >}}
chmod 0640 /ssh/ssh_host_rsa_key_signed.pub
{{< / highlight >}}
<!-- /snippet:sign_host_key_permissions -->

The last step is to make this signed host key known the the SSH server using the `HostCertificate` configuration directive

<!-- file:ssh-with-signed-hostkey/sshd_config -->

{{< github repository="pellepelster/vault-ssh-ca" file="ssh-with-signed-hostkey/sshd_config"  >}}ssh-with-signed-hostkey/sshd_config{{< /github >}}

{{< highlight go "" >}}
Port 22
UsePAM yes
HostKey /ssh/ssh_host_rsa_key

HostCertificate /ssh/ssh_host_rsa_key_signed.pub

{{< / highlight >}}
<!-- /file:ssh-with-signed-hostkey/sshd_config -->

And we are good to go to start the improved SSH server

```
./do start-ssh-with-signed-hostkey
```

Now to be finally able to connect we have to make the CAs public key known to our local SSH client. Vault exposes them via http so we can simply download the public key from `http://localhost:8200/v1/host-ssh/public_key` and add it to SSHs known hosts file with the `@cert-authority` configuration (we are gonna use a seperate `known_hosts` file here, to avoid messing with your real `~/.ssh/known_hosts`)

<!-- snippet:create_known_hosts -->

{{< github repository="pellepelster/vault-ssh-ca" file="do#L109-L109"  >}}do{{< /github >}}

{{< highlight go "" >}}
  echo "@cert-authority localhost $(curl --silent --header "X-Vault-Token: root-token" http://localhost:8200/v1/host-ssh/public_key)" > "known_hosts"
{{< / highlight >}}
<!-- /snippet:create_known_hosts -->

If we run SSH using Bobs key and our special `known_hosts` now

```
ssh -o UserKnownHostsFile=./known_hosts  -p 2022 -i ssh-keys/bob_id_rsa admin-ssh-user@localhost
```

It seamlessy connects to the server and the authenticity is ensured by a trusted CA.

## Creating trusted user keys

For the reverse direction to enable SSH to verify users keys that were signed by a trusted CA we have to take the same steps as before but with switched sides.

Te keep a clear seperation we create a second backend and role for vault to sign the user keys

<!-- snippet:vault_mount_user_ssh -->

{{< github repository="pellepelster/vault-ssh-ca" file="ssh-with-trusted-user-ca/main.tf#L2-L6"  >}}ssh-with-trusted-user-ca/main.tf{{< /github >}}

{{< highlight go "" >}}
resource "vault_mount" "user_ssh" {
  path        = "user-ssh"
  type        = "ssh"
  description = "user-ssh"
}
{{< / highlight >}}
<!-- /snippet:vault_mount_user_ssh -->

As before we also create a corresponding role, configured for user certificates, `allowed_users` and `default_user` are important, otherwise SSH will complain about missing principals in the certificate

<!-- snippet:vault_ssh_secret_backend_role_user_ssh_role -->

{{< github repository="pellepelster/vault-ssh-ca" file="ssh-with-trusted-user-ca/main.tf#L10-L21"  >}}ssh-with-trusted-user-ca/main.tf{{< /github >}}

{{< highlight go "" >}}
resource "vault_ssh_secret_backend_role" "user_ssh_role" {
    name                    = "user-ssh"
    backend                 = vault_mount.user_ssh.path
    key_type                = "ca"
    allow_host_certificates = false
    allow_user_certificates = true
    allowed_users           = "admin-ssh-user"
    default_user            = "admin-ssh-user"
    default_extensions  = {
      permit-pty: ""
    }
}
{{< / highlight >}}
<!-- /snippet:vault_ssh_secret_backend_role_user_ssh_role -->

Like before we have to initially create the keys needed to sign our user keys

<!-- snippet:create_user_signing_key -->

{{< github repository="pellepelster/vault-ssh-ca" file="do#L99-L103"  >}}do{{< /github >}}

{{< highlight go "" >}}
  curl \
    --header "X-Vault-Token: root-token" \
    --request POST \
    --data '{"generate_signing_key": true}' \
    http://localhost:8200/v1/user-ssh/config/ca 
{{< / highlight >}}
<!-- /snippet:create_user_signing_key -->

Now we are good to go, the last thing missing on the server side is to make the user CAs public key known to SSH. First step is to download the public key on container start

<!-- snippet:download_user_ssh_public_key -->

{{< github repository="pellepelster/vault-ssh-ca" file="ssh-with-trusted-user-ca/run.sh#L8-L9"  >}}ssh-with-trusted-user-ca/run.sh{{< /github >}}

{{< highlight go "" >}}
curl --silent http://vault:8200/v1/user-ssh/public_key > /ssh/user_ssh_ca.pub
chmod 0640 /ssh/user_ssh_ca.pub
{{< / highlight >}}
<!-- /snippet:download_user_ssh_public_key -->

and make it known to SSH by pointing `TrustedUserCAKeys` to the previously downloaded public key for the user CA

<!-- file:ssh-with-trusted-user-ca/sshd_config -->

{{< github repository="pellepelster/vault-ssh-ca" file="ssh-with-trusted-user-ca/sshd_config"  >}}ssh-with-trusted-user-ca/sshd_config{{< /github >}}

{{< highlight go "" >}}
Port 22
UsePAM yes
HostKey /ssh/ssh_host_rsa_key
HostCertificate /ssh/ssh_host_rsa_key_signed.pub

TrustedUserCAKeys /ssh/user_ssh_ca.pub
{{< / highlight >}}
<!-- /file:ssh-with-trusted-user-ca/sshd_config -->

Lets start this again improved SSH server

```
./do start-ssh-with-trusted-user-ca
```

Now what we have have to do in order to be able to login with Alice SSH key is to sign it, like with did with the SSH host key in the previous example.
The signing process it also pretty much the same, except this time we can leave out the `cert_type` as user certs are te default when signing keys with vault  

<!-- snippet:sign_alice_key -->

{{< github repository="pellepelster/vault-ssh-ca" file="do#L123-L127"  >}}do{{< /github >}}

{{< highlight go "" >}}
  curl --silent \
    --header "X-Vault-Token: root-token" \
    --request POST \
    --data "{\"public_key\":\"$(cat ssh-keys/alice_id_rsa.pub)\"}" \
    http://localhost:8200/v1/user-ssh/sign/user-ssh | jq -r .data.signed_key > ssh-keys/alice_id_rsa_signed.pub
{{< / highlight >}}
<!-- /snippet:sign_alice_key -->


If we tell our SSH client to also use the signed SSH key, alongside with the normal key, Alice is allowed to log into our SSH server

```
ssh -o UserKnownHostsFile=./known_hosts  -p 3022 -i ssh-keys alice_id_rsa_signed.pub -i ssh-keys/alice_id_rsa admin-ssh-user@localhost
```

## Were to go from here

### Vault Authentication

In our example we used a static root token everywhere. This is of course not how vault is intended to be used. In a real scenario any user taking advantage of vault, like in our example signing user keys in order to log in, would need to authenticate to vault first to obtain a token that could be used for the signing process. Due to vaults large set of [authentication backends](https://www.vaultproject.io/docs/auth/) this enables a lot of interesting usecases, like for example enforcing a user login with two-factor authentication before being able to log in via SSH.

### Signed certificate lifetimes

Another interesting feature is, that the lifetime of the signed user certificates can be limited, by adding a TTL to the roles configuration

{{< highlight go "" >}}
[..]
ttl = "1m0s"
[..]
{{< / highlight >}}

this enables togehter with the various authentication backends to short lived SSH user certificates that expire after a certain ammount of time.