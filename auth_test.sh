export VAULT_ADDR="https://do-not-delete-ever-v2-public-vault-cf6a1d76.5773df81.z1.hashicorp.cloud:8200";
export VAULT_NAMESPACE="admin"

vault login -method=oidc -path=auth0 

vault kv get -namespace=admin -mount="kv" "test"
