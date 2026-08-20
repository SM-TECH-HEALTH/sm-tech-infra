# Passo a passo - configurar Azure + GitHub para a esteira SM-TECH

Este guia leva voce do zero ate o primeiro deploy automatico em `dev`.

Arquitetura final (lab, otimizada para R$ 100/mes):

- **PostgreSQL Flexible Server B1ms** com auto-stop fora do horario comercial
- **Azure Container Apps** (scale-to-zero) servindo a API — Container Apps Environment
  provisionado **sem Log Analytics** (lab); reintroduzir o workspace se for para producao real
- **GitHub Container Registry (GHCR)** como registro de imagens - **gratis**
- **Azure Static Web App Free** para o front Angular (dev) e **site institucional** (prod)
- Front hospitalar em prod usa SWA **Standard**; o institucional permanece **Free** (~R$ 0)

Pre-requisitos:

- Conta Azure com permissao de Owner (ou Contributor + User Access Admin) na subscription.
- Azure CLI instalado e logado (`az login`).
- Acesso de admin nos repos `SM-TECH-HEALTH/sm-tech-back`, `sm-tech-front`, `sm-tech-agents`, `sm-tech-infra` e `sm-tech-site-institucional`.

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
4. Criar federated credentials:
   - `sm-tech-back-development` e `sm-tech-back-production`
   - `sm-tech-front-development` e `sm-tech-front-production`
   - `sm-tech-agents-development` e `sm-tech-agents-production`
   - `sm-tech-site-institucional-production` (site institucional, so prod)
   - `sm-tech-infra-development` (para o workflow agendado)
5. Imprimir no final todos os valores que voce vai colar no GitHub, incluindo sugestoes de senha PostgreSQL e chave JWT.

Copie esses valores ou deixe a janela aberta - voce vai usar agora.

---

## 3. Configurar GitHub Environments

Faca **EM CADA UM** dos repos (`sm-tech-back`, `sm-tech-front`, `sm-tech-agents`, `sm-tech-infra` e `sm-tech-site-institucional`):

> No `sm-tech-infra` voce so precisa criar `development` (e nao `production`), porque o unico workflow desse repo e o `Postgres Schedule` rodando em dev.
>
> No `sm-tech-site-institucional` voce so precisa criar `production` (site publico, SWA Free).

### 3.1 Criar os environments

Em `Settings -> Environments`:

1. Clique em **New environment** e crie `development`.
   - Sem aprovacao obrigatoria.
   - Sem branch protection (deploy via push em `develop`).
2. (back, front e site institucional) Clique em **New environment** e crie `production`.
   - Marque **Required reviewers** e adicione voce/equipe.
   - Em **Deployment branches and tags**, escolha **Selected branches**, permita apenas `main`.

### 3.2 Adicionar Variables

Dentro de cada environment, secao **Environment variables**:

**sm-tech-back, sm-tech-front e sm-tech-agents** (development e production):

| Nome | Valor |
| --- | --- |
| `AZURE_CLIENT_ID` | `<AppId impresso pelo script>` |
| `AZURE_TENANT_ID` | `<TenantId impresso pelo script>` |
| `AZURE_SUBSCRIPTION_ID` | `<SubscriptionId impresso pelo script>` |
| `AZURE_LOCATION` | `brazilsouth` |
| `CORS_ALLOWED_ORIGIN` | (deixe vazio no primeiro deploy) |
| `OPENAI_LOCATION` | `eastus2` (só agents; opcional — o Bicep já usa esse default) |

**sm-tech-site-institucional** (apenas production):

| Nome | Valor |
| --- | --- |
| `AZURE_CLIENT_ID` | `<AppId>` |
| `AZURE_TENANT_ID` | `<TenantId>` |
| `AZURE_SUBSCRIPTION_ID` | `<SubscriptionId>` |

**sm-tech-infra** (apenas development):

| Nome | Valor |
| --- | --- |
| `AZURE_CLIENT_ID` | `<AppId>` |
| `AZURE_TENANT_ID` | `<TenantId>` |
| `AZURE_SUBSCRIPTION_ID` | `<SubscriptionId>` |

### 3.3 Adicionar Secrets

Secao **Environment secrets**, em `sm-tech-back`, `sm-tech-front` e `sm-tech-agents` (development e production):

| Nome | Valor |
| --- | --- |
| `POSTGRES_ADMIN_PASSWORD` | min. 12 caracteres - use a sugestao do script ou a sua |
| `JWT_SECRET_KEY` | min. 32 caracteres - use a sugestao do script ou a sua |

> Use o **mesmo par** de senha/chave nos três repos dentro do mesmo environment — eles provisionam o mesmo resource group via `azd`.
>
> **Não** cadastre a chave do Azure OpenAI no GitHub. O módulo Bicep `openai.bicep` injeta `listKeys` no Container App dos agentes.

No `sm-tech-site-institucional` (production), secret opcional:

| Nome | Valor |
| --- | --- |
| `VITE_WEB3FORMS_ACCESS_KEY` | chave publica Web3Forms (formulario de contato) |

---

## 4. Primeiro deploy de dev

1. Em `sm-tech-back`, faca push em `develop`. O workflow `Deploy API` vai:
   - Provisionar Postgres + Container Apps + Static Web App (~10-15 min na primeira vez).
   - Buildar a imagem Docker e publicar em `ghcr.io/sm-tech-health/sm-tech-back:<sha>`.
   - Atualizar o Container App apontando para essa imagem.

2. **Tornar o pacote GHCR publico** (uma vez so):
   - Abra https://github.com/orgs/SM-TECH-HEALTH/packages/container/sm-tech-back/settings
   - Role ate **Danger Zone** -> **Change package visibility** -> **Public**.
   - Por que: o Container App nao tem credenciais para puxar imagem privada do GHCR. Como o pacote so contem a imagem da API e nao tem segredos embutidos, deixar publico para um lab e aceitavel.

3. Pegue o `WEB_URI` (URL `<...>.azurestaticapps.net`) impresso pelo `azd` e cole em `CORS_ALLOWED_ORIGIN` nos environments `development` de **back, front e agents**.

4. Em `sm-tech-front`, faca push em `develop`. O workflow `Deploy Web` publica o front no Static Web App.

5. Verifique a aplicacao no `WEB_URI`.

6. Em `sm-tech-infra`, va em **Actions -> Postgres Schedule -> Run workflow** uma vez (acao `stop`) para validar que a credencial OIDC esta ok. Depois o cron toma conta sozinho.

7. **Agentes de IA** (opcional, gera custo de tokens gpt-4o):
   1. Rode de novo `.\scripts\setup-azure-oidc.ps1` (idempotente) para criar as federated credentials `sm-tech-agents-*`, **ou** crie-as na App Registration se o script ja tiver rodado antes desta mudanca.
   2. Crie o repo GitHub `SM-TECH-HEALTH/sm-tech-agents` (se ainda for so local), environments `development`/`production` com as mesmas variables/secrets do back.
   3. **Antes do primeiro provision:** no portal Azure, peca quota de `gpt-4o` em `eastus2` (Foundry / Azure OpenAI). Sem quota o `azd provision` dos agentes falha; a API continua no ar porque `DEPLOY_AI_AGENTS` so e `true` nesse workflow.
   4. Push em `develop` no `sm-tech-agents`. O workflow cria o recurso OpenAI + Container App `agents`, publica `ghcr.io/sm-tech-health/sm-tech-agents` e atualiza a imagem.
   5. Torne o pacote GHCR **publico** (mesmo motivo da API).
   6. Re-rode o deploy do front: o build injeta o FQDN dos agentes em `environment.azuredev.ts`.
   7. No SPA (modulo Command Center): **Assistentes de IA → Assistente de Relatórios MV**.

---

## 5. Promover para producao

1. Garanta que `main` esta em sincronia com a versao testada de `develop`.
2. Faca merge/push em `main`.
3. No GitHub Actions, o job `deploy-prod` fica **Waiting** ate voce aprovar (porque `production` tem Required reviewers).
4. Aprove. O workflow provisiona o ambiente `prod` separado (PostgreSQL maior, SWA Standard no front hospitalar, SWA Free do site institucional, Container Apps com 1-3 replicas).

---

## 5.1 Site institucional (`smtechsistemas.com.br`)

O site vive no repo `sm-tech-site-institucional` e usa um **segundo** Static Web App (tag `azd-service-name=site`), criado **somente em prod**, SKU **Free** (~R$ 0).

1. Garanta que o Bicep com o modulo `site` ja foi aplicado via `azd provision` de prod (passo 5 acima).
2. No GitHub do site: environment `production` com as variables OIDC (passo 3.2) e, se usar o formulario Web3Forms, o secret `VITE_WEB3FORMS_ACCESS_KEY`.
3. Push em `main` (ou **Actions -> Deploy Site -> Run workflow**). O job publica `dist/` no SWA Free.
4. Confira o output `SITE_URI` (`https://<...>.azurestaticapps.net`).
5. Domínio custom:

```powershell
# Na raiz do sm-tech-infra, logado no Azure:
.\scripts\configure-site-domain.ps1
```

O script registra `smtechsistemas.com.br` e `www.smtechsistemas.com.br` e imprime os registros DNS (CNAME do `www`, TXT `_dnsauth` + ALIAS/ANAME/A do apex). Crie os registros no provedor DNS e acompanhe:

```powershell
.\scripts\configure-site-domain.ps1 -Status
```

> O DNS continua no provedor atual (nao ha Azure DNS Zone nesta infra). SWA Free nao faz redirect host-based nativo; se quiser forcar `www` -> apex, configure no DNS/provedor. O canonical do site ja aponta para `https://smtechsistemas.com.br`.

---

## 6. Custos esperados (Brazil South, dev only)

| Recurso | SKU | Estimativa |
| --- | --- | --- |
| PostgreSQL Flexible Server | B1ms, 32 GB, ~60h/semana ligado | ~R$ 20-25/mes (compute) + ~R$ 16/mes (storage) |
| Container Apps (API) | min 0 replicas, scale-to-zero | R$ 0 idle, ~R$ 0-10/mes uso leve |
| Container Apps (agentes, se ligado) | min 0 replicas, scale-to-zero | R$ 0 idle + tokens gpt-4o (credito startup) |
| Azure OpenAI / Foundry (`DEPLOY_AI_AGENTS=true`) | gpt-4o GlobalStandard ~10k TPM | so tokens; cobrado na mesma subscription |
| Container Apps Environment | Consumo, sem Log Analytics | R$ 0 fixo |
| Azure Static Web App (front) | Free | R$ 0 |
| Azure Static Web App (site institucional, so prod) | Free | R$ 0 |
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
- **CORS bloqueando o front**: `CORS_ALLOWED_ORIGIN` precisa ser o dominio exato do Static Web App, com `https://` e sem `/` no final. Re-rode o deploy do back (e o dos agentes, se ja existirem).
- **`az containerapp update` nao encontra o app**: rode antes `azd provision`. O `update` da API filtra `azd-service-name==api`; o dos agentes filtra `agents`.
- **Quota gpt-4o recusada no provision dos agentes**: peca o modelo em `eastus2` no portal (Azure OpenAI / Foundry). Nao rode o workflow de novo ate a quota existir. Se o `azd env` ficou com `DEPLOY_AI_AGENTS=true` e o deploy da API passou a falhar, `azd env set DEPLOY_AI_AGENTS false` no ambiente `dev` e re-rode a API; depois volte a `true` so no workflow agents.
- **Chat 401 no SPA**: `JWT_SECRET_KEY` do environment agents tem de ser **identico** ao da API. CORS dos agentes tem de ser o `WEB_URI` (mesmo `CORS_ALLOWED_ORIGIN`).
- **Deploy Site nao encontra o SWA**: o modulo `site` so existe em prod. Rode `azd provision` no ambiente prod (pipeline do front/back) apos o merge do Bicep; confira a tag `azd-service-name=site`.
- **Dominio custom pendente**: confira TXT `_dnsauth` e ALIAS/CNAME com `.\scripts\configure-site-domain.ps1 -Status`.
