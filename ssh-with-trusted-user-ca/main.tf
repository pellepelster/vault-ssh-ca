# snippet:vault_mount_user_ssh
resource "vault_mount" "user_ssh" {
  path        = "user-ssh"
  type        = "ssh"
  description = "user-ssh"
}
# /snippet:vault_mount_user_ssh

# snippet:vault_ssh_secret_backend_role_user_ssh_role
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
# /snippet:vault_ssh_secret_backend_role_user_ssh_role
