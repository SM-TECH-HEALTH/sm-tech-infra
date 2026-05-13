# Passo a passo - configurar Azure + GitHub para a esteira SM-TECH

Este guia leva voce do zero ate o primeiro deploy automatico em `dev`.

Arquitetura final (lab, otimizada para R$ 100/mes):

- **PostgreSQL Flexible Server B1ms** com auto-stop fora do horario comercial
- **Azure Container Apps** (scale-to-zero) servindo a API
- **GitHub Container Registry (GHCR)** como registro de imagens - **gratis**
- **Azure Static Web App Free** para o front Angular
- **Log Analytics free tier**

Pre-requisitos:

- Conta Azure com permissao de Owner (ou Contributor + User Access Admin) na subscription.
- Azure CLI instalado e logado (`az login`).
- Acesso de admin nos repos `SM-TECH-HEALTH/sm-tech-back`, `sm-tech-front` e `sm-tech-infra`.

---

## 1. Selecionar a subscription correta

```powershell
az account list --output table
az account set --subscription "<id-ou-nome-da-subscription>"
az account show
```

Confirme que a subscription mostrada e a correta antes de continuar.

---

## 2. Rodar o script de setup do Azure

No PowerShell, na raiz do `sm-tech-infra`:

```powershell
.\scripts\setup-azure-oidc.ps1
```

O script vai:

1. Criar a App Registration `sm-tech-github-actions`.
2. Criar o Service Principal correspondente.
3. Conceder os papeis **Contributor** e **User Access Administrator** na subscription.
4. Criar 5 federated credentials:
   - `sm-tech-back-development` e `sm-tech-back-production`
   - `sm-tech-front-development` e `sm-tech-front-production`
   - `sm-tech-infra-development` (para o workflow agendado)
5. Imprimir no final todos os valores que voce vai colar no GitHub, incluindo sugestoes de senha PostgreSQL e chave JWT.

Copie esses valores ou deixe a janela aberta - voce vai usar agora.

---

## 3. Configurar GitHub Environments

Faca **EM CADA UM** dos repos (`sm-tech-back`, `sm-tech-front` e `sm-tech-infra`):

> No `sm-tech-infra` voce so precisa criar `development` (e nao `production`), porque o unico workflow desse repo e o `Postgres Schedule` rodando em dev.

### 3.1 Criar os environments

Em `Settings -> Environments`:

1. Clique em **New environment** e crie `development`.
   - Sem aprovacao obrigatoria.
   - Sem branch protection (deploy via push em `develop`).
2. (so back e front) Clique em **New environment** e crie `production`.
   - Marque **Required reviewers** e adicione voce/equipe.
   - Em **Deployment branches and tags**, escolha **Selected branches**, permita apenas `main`.

### 3.2 Adicionar Variables

Dentro de cada environment, secao **Environment variables**:

**sm-tech-back e sm-tech-front** (development e production):

| Nome | Valor |
| --- | --- |
| `AZURE_CLIENT_ID` | `<AppId impresso pelo script>` |
| `AZURE_TENANT_ID` | `<TenantId impresso pelo script>` |
| `AZURE_SUBSCRIPTION_ID` | `<SubscriptionId impresso pelo script>` |
| `AZURE_LOCATION` | `brazilsouth` |
| `CORS_ALLOWED_ORIGIN` | (deixe vazio no primeiro deploy) |

**sm-tech-infra** (apenas development):

| Nome | Valor |
| --- | --- |
| `AZURE_CLIENT_ID` | `<AppId>` |
| `AZURE_TENANT_ID` | `<TenantId>` |
| `AZURE_SUBSCRIPTION_ID` | `<SubscriptionId>` |

### 3.3 Adicionar Secrets

Secao **Environment secrets**, apenas em `sm-tech-back` e `sm-tech-front` (development e production):

| Nome | Valor |
| --- | --- |
| `POSTGRES_ADMIN_PASSWORD` | min. 12 caracteres - use a sugestao do script ou a sua |
| `JWT_SECRET_KEY` | min. 32 caracteres - use a sugestao do script ou a sua |

> Use o **mesmo par** de senha/chave nos dois repos (back e front) dentro do mesmo environment - eles provisionam o mesmo recurso via `azd`.

---

## 4. Primeiro deploy de dev

1. Em `sm-tech-back`, faca push em `develop`. O workflow `Deploy API` vai:
   - Provisionar Postgres + Container Apps + Log Analytics + Static Web App (~10-15 min na primeira vez).
   - Buildar a imagem Docker e publicar em `ghcr.io/sm-tech-health/sm-tech-back:<sha>`.
   - Atualizar o Container App apontando para essa imagem.

2. **Tornar o pacote GHCR publico** (uma vez so):
   - Abra https://github.com/orgs/SM-TECH-HEALTH/packages/container/sm-tech-back/settings
   - Role ate **Danger Zone** -> **Change package visibility** -> **Public**.
   - Por que: o Container App nao tem credenciais para puxar imagem privada do GHCR. Como o pacote so contem a imagem da API e nao tem segredos embutidos, deixar publico para um lab e aceitavel.

3. Pegue o `WEB_URI` (URL `<...>.azurestaticapps.net`) impresso pelo `azd` e cole em `CORS_ALLOWED_ORIGIN` nos environments `development` de **back e front**.

4. Em `sm-tech-front`, faca push em `develop`. O workflow `Deploy Web` publica o front no Static Web App.

5. Verifique a aplicacao no `WEB_URI`.

6. Em `sm-tech-infra`, va em **Actions -> Postgres Schedule -> Run workflow** uma vez (acao `stop`) para validar que a credencial OIDC esta ok. Depois o cron toma conta sozinho.

---

## 5. Promover para producao

1. Garanta que `main` esta em sincronia com a versao testada de `develop`.
2. Faca merge/push em `main`.
3. No GitHub Actions, o job `deploy-prod` fica **Waiting** ate voce aprovar (porque `production` tem Required reviewers).
4. Aprove. O workflow provisiona o ambiente `prod` separado (PostgreSQL maior, SWA Standard, Container Apps com 1-3 replicas).

---

## 6. Custos esperados (Brazil South, dev only)

| Recurso | SKU | Estimativa |
| --- | --- | --- |
| PostgreSQL Flexible Server | B1ms, 32 GB, ~60h/semana ligado | ~R$ 20-25/mes (compute) + ~R$ 16/mes (storage) |
| Container Apps (API) | min 0 replicas, scale-to-zero | R$ 0 idle, ~R$ 0-10/mes uso leve |
| Container Apps Environment | Consumo | R$ 0 fixo |
| Log Analytics Workspace | PerGB2018, 7 dias | gratis ate 5GB/mes |
| Azure Static Web App | Free | R$ 0 |
| **GitHub Container Registry** | publico, ate 500MB free | **R$ 0** |

**Total dev: ~R$ 35-55/mes.** Bem dentro do teto de R$ 100.

### Como o auto-stop do Postgres funciona

O workflow `.github/workflows/postgres-schedule.yml` (no `sm-tech-infra`) usa cron do GitHub Actions:

- **Start** as 11:00 UTC (08:00 BRT) seg-sex
- **Stop** as 23:00 UTC (20:00 BRT) todo dia

Postgres `Stopped` paga apenas storage. O serviço auto-reinicia depois de 7 dias parados; o stop diario garante que ele volta a parar caso isso aconteca no fim de semana.

Para parar/iniciar manualmente: **Actions -> Postgres Schedule -> Run workflow** -> escolher `start` ou `stop`.

---

## 7. Troubleshooting rapido

- **Workflow falha com 403 no Azure**: o SP nao tem permissao. Rode o script de setup de novo (e idempotente).
- **Federated credential nao bate**: o subject e `repo:SM-TECH-HEALTH/<repo>:environment:<env>`. O environment precisa existir no GitHub **antes** do primeiro run.
- **Container App fica em "Activation failed: Unable to pull image"**: o pacote GHCR esta privado. Refaca o passo 4.2 (Change visibility -> Public).
- **Postgres falha com senha curta**: precisa de minimo 12 caracteres. Atualize o secret e re-rode.
- **CORS bloqueando o front**: `CORS_ALLOWED_ORIGIN` precisa ser o dominio exato do Static Web App, com `https://` e sem `/` no final. Re-rode o deploy do back.
- **`az containerapp update` nao encontra o app**: rode antes `azd provision` (o passo de "Provision infrastructure" do workflow ja faz isso). O `update` procura pela tag `azd-env-name`.
