provider "auth0" {
  domain        =  var.auth0_domain
  debug = true
}

resource "auth0_client" "vault_oidc_app" {
  name = "Vault OIDC App"
description     = "App for running OIDC Auth in Vault"

  app_type = "regular_web"
  callbacks = [
    "http://localhost:8250/oidc/callback","${var.vault_addr}/ui/vault/auth/auth0/oidc/callback", # Vault's OIDC callback URL
  ]

  oidc_conformant = true

  jwt_configuration {
    alg = "RS256"
  }
}


data "auth0_client" "vault_oidc_app" {
  client_id = auth0_client.vault_oidc_app.client_id
}