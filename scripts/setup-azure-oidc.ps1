# =====================================================================
# Setup Azure OIDC para GitHub Actions - SM-TECH
# =====================================================================
# Pre-requisitos:
#   - Azure CLI instalado (az --version)
#   - Logado: az login
#   - Subscription correta selecionada: az account set --subscription <id>
#
# O que esse script faz:
#   1. Cria App Registration + Service Principal
#   2. Concede Contributor + User Access Administrator no escopo da subscription
#   3. Cria federated credentials:
#        - sm-tech-back/environment:development e production
#        - sm-tech-front/environment:development e production
#        - sm-tech-agents/environment:development e production
#        - sm-tech-site-institucional/environment:production (site institucional, so prod)
#        - sm-tech-infra/environment:development (Postgres schedule)
#   4. Imprime no final os valores que voce vai usar no GitHub
# =====================================================================

$ErrorActionPreference = "Stop"

# ---- Parametros (ajuste se necessario) ----
$AppName        = "sm-tech-github-actions"
$GithubOrg      = "SM-TECH-HEALTH"
$Repos          = @("sm-tech-back", "sm-tech-front", "sm-tech-agents")
$Environments   = @("development", "production")
# Site institucional: so production.
# Este repo usa subject com owner_id/repo_id (claim personalizado no GitHub Org).
$SiteRepo       = "sm-tech-site-institucional"
$SiteEnv        = "production"
$SiteOrgId      = "280150824"
$SiteRepoId     = "1331169593"
$SiteSubject    = "repo:${GithubOrg}@${SiteOrgId}/${SiteRepo}@${SiteRepoId}:environment:${SiteEnv}"
# Fallback: formato classico sem IDs (caso a org desative claims customizados).
$SiteSubjectClassic = "repo:${GithubOrg}/${SiteRepo}:environment:${SiteEnv}"
# sm-tech-infra precisa de credencial extra porque o workflow agendado
# de start/stop do Postgres roda nesse repo.
$InfraRepo      = "sm-tech-infra"
$InfraEnv       = "development"

Write-Host "==> Verificando login no Azure..." -ForegroundColor Cyan
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Voce nao esta logado. Execute: az login" -ForegroundColor Red
    exit 1
}
Write-Host "  Subscription: $($account.name) ($($account.id))" -ForegroundColor Green
Write-Host "  Tenant:       $($account.tenantId)" -ForegroundColor Green

$SubscriptionId = $account.id
$TenantId       = $account.tenantId

# ---- 1. Criar (ou reutilizar) App Registration ----
Write-Host ""
Write-Host "==> 1/4 App Registration '$AppName'..." -ForegroundColor Cyan
$AppId = az ad app list --display-name $AppName --query "[0].appId" -o tsv --only-show-errors
if ([string]::IsNullOrWhiteSpace($AppId)) {
    Write-Host "  Criando App Registration..." -ForegroundColor DarkGray
    az ad app create --display-name $AppName --only-show-errors | Out-Null
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Seconds 5
        $AppId = az ad app list --display-name $AppName --query "[0].appId" -o tsv --only-show-errors
        if (-not [string]::IsNullOrWhiteSpace($AppId)) { break }
        Write-Host "  Aguardando propagacao da App..." -ForegroundColor DarkGray
    }
}
if ([string]::IsNullOrWhiteSpace($AppId)) {
    Write-Host "Falha ao obter o AppId apos varias tentativas." -ForegroundColor Red
    exit 1
}
Write-Host "  AppId: $AppId" -ForegroundColor Green

# ---- 2. Criar (ou reutilizar) Service Principal ----
Write-Host ""
Write-Host "==> 2/4 Service Principal..." -ForegroundColor Cyan
# Usa `az ad sp list --filter` em vez de `az ad sp show` para que SP inexistente
# nao gere erro (show retorna stderr e mata o script com ErrorActionPreference=Stop).
$existingSp = az ad sp list --filter "appId eq '$AppId'" --query "[0].id" -o tsv --only-show-errors
if ([string]::IsNullOrWhiteSpace($existingSp)) {
    Write-Host "  Criando Service Principal..." -ForegroundColor DarkGray
    az ad sp create --id $AppId --only-show-errors | Out-Null
    # AAD precisa de tempo para propagar antes de aparecer no list
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Seconds 5
        $existingSp = az ad sp list --filter "appId eq '$AppId'" --query "[0].id" -o tsv --only-show-errors
        if (-not [string]::IsNullOrWhiteSpace($existingSp)) { break }
        Write-Host "  Aguardando propagacao do SP..." -ForegroundColor DarkGray
    }
}
$SpObjectId = $existingSp
if ([string]::IsNullOrWhiteSpace($SpObjectId)) {
    Write-Host "Falha ao obter o Object ID do Service Principal apos varias tentativas." -ForegroundColor Red
    exit 1
}
Write-Host "  SP Object ID: $SpObjectId" -ForegroundColor Green

# ---- 3. Role Assignments ----
Write-Host ""
Write-Host "==> 3/4 Role assignments na subscription..." -ForegroundColor Cyan
$scope = "/subscriptions/$SubscriptionId"

foreach ($role in @("Contributor", "User Access Administrator")) {
    Write-Host "  -> $role"
    # PrincipalNotFound pode acontecer logo apos criar o SP - retry alguns segundos
    $attempts = 0
    while ($attempts -lt 6) {
        az role assignment create `
            --assignee-object-id $SpObjectId `
            --assignee-principal-type ServicePrincipal `
            --role $role `
            --scope $scope `
            --only-show-errors 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { break }
        $attempts++
        Start-Sleep -Seconds 5
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  AVISO: nao consegui atribuir $role (pode ja existir)" -ForegroundColor Yellow
    }
}
Write-Host "  Ok" -ForegroundColor Green

# ---- 4. Federated Credentials ----
Write-Host ""
Write-Host "==> 4/4 Federated credentials..." -ForegroundColor Cyan

function New-FederatedCredential {
    param([string]$CredName, [string]$Subject)

    $exists = az ad app federated-credential list --id $AppId --query "[?name=='$CredName'].name" -o tsv --only-show-errors
    if ($exists) {
        Write-Host "  -> $CredName (ja existe)" -ForegroundColor DarkGray
        return
    }

    $payload = @{
        name      = $CredName
        issuer    = "https://token.actions.githubusercontent.com"
        subject   = $Subject
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json -Compress

    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $payload -Encoding utf8
    az ad app federated-credential create --id $AppId --parameters "@$tmp" --only-show-errors | Out-Null
    Remove-Item $tmp
    Write-Host "  -> $CredName  (subject: $Subject)" -ForegroundColor Green
}

# back e front: 2 envs cada
foreach ($repo in $Repos) {
    foreach ($envName in $Environments) {
        New-FederatedCredential -CredName "$repo-$envName" `
            -Subject "repo:$GithubOrg/${repo}:environment:$envName"
    }
}

# site institucional: so production (subject com IDs + fallback classico)
New-FederatedCredential -CredName "$SiteRepo-$SiteEnv" `
    -Subject $SiteSubject
New-FederatedCredential -CredName "$SiteRepo-$SiteEnv-classic" `
    -Subject $SiteSubjectClassic

# sm-tech-infra: 1 env para o workflow agendado de cost-saving
New-FederatedCredential -CredName "$InfraRepo-$InfraEnv" `
    -Subject "repo:$GithubOrg/${InfraRepo}:environment:$InfraEnv"

# ---- Resumo ----
Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Yellow
Write-Host " GUARDE ESSES VALORES - voce vai colar no GitHub                     " -ForegroundColor Yellow
Write-Host "=====================================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Variables - cole nos repos:"
Write-Host "  sm-tech-back               -> Environments > development e production > Variables"
Write-Host "  sm-tech-front              -> Environments > development e production > Variables"
Write-Host "  sm-tech-agents             -> Environments > development e production > Variables"
Write-Host "  sm-tech-site-institucional -> Environments > production > Variables"
Write-Host "  sm-tech-infra              -> Environments > development > Variables"
Write-Host "  AZURE_CLIENT_ID         = $AppId"
Write-Host "  AZURE_TENANT_ID         = $TenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID   = $SubscriptionId"
Write-Host "  AZURE_LOCATION          = brazilsouth      (back/front/agents)"
Write-Host "  CORS_ALLOWED_ORIGIN     = (deixe vazio no primeiro deploy. back/front/agents)"
Write-Host "  OPENAI_LOCATION         = eastus2           (so agents; gpt-4o quase nunca esta em brazilsouth)"
Write-Host ""
Write-Host "Secrets (em CADA repo back/front/agents, no escopo do environment):"
Write-Host "  POSTGRES_ADMIN_PASSWORD = (gere uma senha forte com min. 12 chars)"
Write-Host "  JWT_SECRET_KEY          = (gere uma chave forte com min. 32 chars)"
Write-Host "  Use o mesmo par nos tres repos. A chave OpenAI NAO vai no GitHub — o Bicep injeta via listKeys."
Write-Host ""
Write-Host "Secret opcional no site institucional (production):"
Write-Host "  VITE_WEB3FORMS_ACCESS_KEY = (chave publica Web3Forms, se o formulario usar API)"
Write-Host ""
Write-Host "Sugestoes prontas (copie se nao tiver suas proprias):"
# So alfanumerico para evitar problemas com escape JSON, expansao de shell
# e caracteres reservados pelo PostgreSQL/connection-string.
$alphabet = (([char[]](48..57)) + ([char[]](65..90)) + ([char[]](97..122)))
$pgPwd  = -join (1..24 | ForEach-Object { $alphabet | Get-Random })
$jwtKey = -join (1..48 | ForEach-Object { $alphabet | Get-Random })
Write-Host "  POSTGRES_ADMIN_PASSWORD = $pgPwd"
Write-Host "  JWT_SECRET_KEY          = $jwtKey"
Write-Host ""
Write-Host "Pronto." -ForegroundColor Green
