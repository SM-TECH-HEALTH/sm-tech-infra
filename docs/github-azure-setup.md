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
for repo in sm-tech-back sm-tech-front sm-tech-agents; do
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

# Site institucional: so production
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{
    \"name\": \"sm-tech-site-institucional-production\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:SM-TECH-HEALTH/sm-tech-site-institucional:environment:production\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
```

Preferivel: rode `.\scripts\setup-azure-oidc.ps1` (idempotente) em vez dos comandos manuais.

## 4. Configurar GitHub Environments

Em `sm-tech-back`, `sm-tech-front` e `sm-tech-agents`, crie:

- Environment `development`, sem aprovação obrigatória.
- Environment `production`, com Required reviewers e branch restriction para `main`.

Em `sm-tech-site-institucional`, crie apenas:

- Environment `production`, com Required reviewers e branch restriction para `main`.

Configure as mesmas variables OIDC (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) em todos. Back/front/agents tambem usam `AZURE_LOCATION` e `CORS_ALLOWED_ORIGIN`. No `sm-tech-agents`, opcional: `OPENAI_LOCATION` (`eastus2`).

Variables:

- `AZURE_CLIENT_ID`: valor de `$APP_ID`
- `AZURE_TENANT_ID`: valor de `$TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`: valor de `$SUBSCRIPTION_ID`
- `AZURE_LOCATION`: exemplo `brazilsouth` (back/front/agents)
- `CORS_ALLOWED_ORIGIN`: URL do front permitido pela API e pelos agentes. Pode ficar vazio no primeiro provisionamento para usar a URL default do Static Web App.
- `OPENAI_LOCATION` (só agents, opcional): `eastus2`. gpt-4o quase nunca está em `brazilsouth`.

Observacao: o template usa `eastus2` como regiao default do Azure Static Web App, porque SWA nao esta disponivel em todas as regioes.

Secrets (back/front/agents — **o mesmo par** nos três, porque `azd provision` reaplica o resource group inteiro):

- `POSTGRES_ADMIN_PASSWORD`: senha forte do PostgreSQL, minimo 12 caracteres.
- `JWT_SECRET_KEY`: chave JWT forte, minimo 32 caracteres. Tem de ser a mesma da API: o Container App dos agentes valida o Bearer do SPA.

Não coloque `AZURE_OPENAI_API_KEY` no GitHub. O Bicep lê a chave com `listKeys` e injeta como secret do Container App.

Secret opcional (site institucional):

- `VITE_WEB3FORMS_ACCESS_KEY`: chave publica Web3Forms para o formulario.

## 5. Branches

- Push em `develop`: deploy automatico para `development` / ambiente azd `dev` (back/front).
- Push em `main`: deploy para `production` / ambiente azd `prod` apenas apos aprovacao no GitHub.
- Site institucional: push em `main` publica no SWA Free de prod (apos o recurso existir via `azd provision`).
