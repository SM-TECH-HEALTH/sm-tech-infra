# Configuracao GitHub Actions + Azure OIDC

Este projeto usa GitHub Actions com OpenID Connect (OIDC), sem secret de senha do service principal.

## 1. Criar app registration e service principal

```bash
az ad app create --display-name sm-tech-github-actions
APP_ID=$(az ad app list --display-name sm-tech-github-actions --query "[0].appId" -o tsv)
az ad sp create --id "$APP_ID"
SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

## 2. Conceder permissoes no Azure

O pipeline cria recursos e tambem cria role assignments para ACR. Por isso, use `Contributor` e `User Access Administrator` no escopo da subscription ou no escopo do resource group escolhido.

```bash
SUBSCRIPTION_SCOPE="/subscriptions/$SUBSCRIPTION_ID"

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role Contributor \
  --scope "$SUBSCRIPTION_SCOPE"

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope "$SUBSCRIPTION_SCOPE"
```

## 3. Criar credenciais federadas

Crie uma credencial por repositório e environment usado no workflow.

```bash
for repo in sm-tech-back sm-tech-front; do
  for env in development production; do
    az ad app federated-credential create \
      --id "$APP_ID" \
      --parameters "{
        \"name\": \"${repo}-${env}\",
        \"issuer\": \"https://token.actions.githubusercontent.com\",
        \"subject\": \"repo:SM-TECH-HEALTH/${repo}:environment:${env}\",
        \"audiences\": [\"api://AzureADTokenExchange\"]
      }"
  done
done
```

## 4. Configurar GitHub Environments

Em `sm-tech-back` e `sm-tech-front`, crie:

- Environment `development`, sem aprovação obrigatória.
- Environment `production`, com Required reviewers e branch restriction para `main`.

Configure as mesmas variables/secrets em ambos os repositórios.

Variables:

- `AZURE_CLIENT_ID`: valor de `$APP_ID`
- `AZURE_PRINCIPAL_ID`: valor de `$SP_OBJECT_ID`
- `AZURE_TENANT_ID`: valor de `$TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`: valor de `$SUBSCRIPTION_ID`
- `AZURE_LOCATION`: exemplo `brazilsouth`
- `CORS_ALLOWED_ORIGIN`: URL do front permitido pela API. Pode ficar vazio no primeiro provisionamento para usar a URL default do Static Web App.

Observacao: o template usa `eastus2` como regiao default do Azure Static Web App, porque SWA nao esta disponivel em todas as regioes.

Secrets:

- `POSTGRES_ADMIN_PASSWORD`: senha forte do PostgreSQL, minimo 12 caracteres.
- `JWT_SECRET_KEY`: chave JWT forte, minimo 32 caracteres.

## 5. Branches

- Push em `develop`: deploy automatico para `development` / ambiente azd `dev`.
- Push em `main`: deploy para `production` / ambiente azd `prod` apenas apos aprovacao no GitHub.
