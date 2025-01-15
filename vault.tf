provider "vault" {
  address = var.vault_addr # Replace with your Vault server address

}


resource "vault_jwt_auth_backend" "oidc_config" {
   type = "oidc"
  path = "auth0"
  description = "OIDC Authentication with Auth0"
  oidc_discovery_url = "https://${var.auth0_domain}/"
  oidc_client_id    = data.auth0_client.vault_oidc_app.client_id
  oidc_client_secret = data.auth0_client.vault_oidc_app.client_secret
  default_role      = "default"
  tune {
        listing_visibility = "unauth"
    }
}


resource "vault_jwt_auth_backend_role" "default_role" {
  backend           = vault_jwt_auth_backend.oidc_config.path
  role_name         = "default"
  allowed_redirect_uris = [
    "${var.vault_addr}/ui/vault/auth/${vault_jwt_auth_backend.oidc_config.path}/oidc/callback",
    "http://localhost:8250/oidc/callback", # Match the callback URI configured in Auth0
  ]
  bound_audiences = [
    auth0_client.vault_oidc_app.client_id,
  ]
  
  user_claim = "sub"
  # groups_claim = "https://vault/groups" # Optional: Customize with your claim for group mapping
  token_policies = ["default","hcp-root"]
  verbose_oidc_logging = true
}