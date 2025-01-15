variable "auth0_domain" {
    description = "your Auth0 dev domain"
    type = string
    default = "dev-3plwnv4yrz1yqut0.us.auth0.com"
}

variable "vault_addr" {
    description = "your Vault Address"
    type = string
    default = "https://do-not-delete-ever-v2-public-vault-cf6a1d76.5773df81.z1.hashicorp.cloud:8200"
}