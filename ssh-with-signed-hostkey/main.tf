# snippet:vault_mount_host_ssh
resource "vault_mount" "host_ssh" {
  path        = "host-ssh"
  type        = "ssh"
  description = "host-ssh"
}
# /snippet:vault_mount_host_ssh

# snippet:vault_ssh_secret_backend_role_host_ssh_role
resource "vault_ssh_secret_backend_role" "host_ssh_role" {
    name                    = "host-ssh"
    backend                 = vault_mount.host_ssh.path
    key_type                = "ca"
    allow_host_certificates = true
    allow_user_certificates = false
}
# /snippet:vault_ssh_secret_backend_role_host_ssh_role

