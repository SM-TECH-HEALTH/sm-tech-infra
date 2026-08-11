# =====================================================================
# Configura dominio custom do site institucional no Azure Static Web App
# =====================================================================
# Pre-requisitos:
#   - Azure CLI instalado e logado (az login)
#   - SWA do site ja provisionado em prod (tag azd-service-name=site)
#   - Permissao para alterar o Static Web App
#
# Uso:
#   .\scripts\configure-site-domain.ps1
#   .\scripts\configure-site-domain.ps1 -Status
#   .\scripts\configure-site-domain.ps1 -ApexDomain "smtechsistemas.com.br" -WwwHost "www.smtechsistemas.com.br"
#
# Fluxo recomendado:
#   1. Rode o script (sem -Status) para registrar os hostnames no SWA.
#   2. Crie os registros DNS que o script imprimir no provedor do dominio.
#   3. Aguarde propagacao DNS e rode de novo (ou use -Status) ate Ready.
# =====================================================================

[CmdletBinding()]
param(
    [string]$EnvironmentName = "prod",
    [string]$ApexDomain = "smtechsistemas.com.br",
    [string]$WwwHost = "www.smtechsistemas.com.br",
    [switch]$Status
)

$ErrorActionPreference = "Stop"

Write-Host "==> Verificando login no Azure..." -ForegroundColor Cyan
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Voce nao esta logado. Execute: az login" -ForegroundColor Red
    exit 1
}
Write-Host "  Subscription: $($account.name) ($($account.id))" -ForegroundColor Green

Write-Host ""
Write-Host "==> Localizando Static Web App (env=$EnvironmentName, service=site)..." -ForegroundColor Cyan
$swaName = az staticwebapp list `
    --query "[?tags.\"azd-env-name\"=='$EnvironmentName' && tags.\"azd-service-name\"=='site'].name | [0]" `
    -o tsv --only-show-errors

if ([string]::IsNullOrWhiteSpace($swaName)) {
    Write-Host "SWA do site institucional nao encontrado." -ForegroundColor Red
    Write-Host "Provision o ambiente prod (azd provision) apos o Bicep com o modulo site." -ForegroundColor Yellow
    exit 1
}

$defaultHostname = az staticwebapp show --name $swaName --query "defaultHostname" -o tsv --only-show-errors
$resourceGroup = az staticwebapp show --name $swaName --query "resourceGroup" -o tsv --only-show-errors
Write-Host "  Nome:     $swaName" -ForegroundColor Green
Write-Host "  RG:       $resourceGroup" -ForegroundColor Green
Write-Host "  Default:  https://$defaultHostname" -ForegroundColor Green

function Get-Hostnames {
    az staticwebapp hostname list `
        --name $swaName `
        --resource-group $resourceGroup `
        --output json --only-show-errors | ConvertFrom-Json
}

function Show-HostnameStatus {
    $hosts = Get-Hostnames
    Write-Host ""
    Write-Host "==> Hostnames registrados" -ForegroundColor Cyan
    if (-not $hosts -or @($hosts).Count -eq 0) {
        Write-Host "  (nenhum hostname custom)" -ForegroundColor DarkGray
        return
    }
    foreach ($h in @($hosts)) {
        $domain = $h.domainName
        if (-not $domain) { $domain = $h.name }
        $state = $h.status
        if (-not $state) {
            if ($h.validationToken) { $state = "(token pendente)" } else { $state = "desconhecido" }
        }
        Write-Host "  - $domain  [$state]" -ForegroundColor White
        if ($h.validationToken) {
            Write-Host "      validationToken: $($h.validationToken)" -ForegroundColor Yellow
        }
    }
}

if ($Status) {
    Show-HostnameStatus
    Write-Host ""
    Write-Host "Default hostname (CNAME/ALIAS destino): $defaultHostname" -ForegroundColor Cyan
    exit 0
}

function Register-Hostname {
    param([string]$Hostname)

    Write-Host ""
    Write-Host "==> Registrando hostname: $Hostname" -ForegroundColor Cyan
    $existing = Get-Hostnames | Where-Object {
        $_.domainName -eq $Hostname -or $_.name -eq $Hostname
    }
    if ($existing) {
        Write-Host "  Ja registrado (status: $($existing.status))" -ForegroundColor DarkGray
        return
    }

    az staticwebapp hostname set `
        --name $swaName `
        --resource-group $resourceGroup `
        --hostname $Hostname `
        --only-show-errors | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Falha ao registrar $Hostname. Confira DNS/permissoes e tente de novo." -ForegroundColor Red
        exit 1
    }
    Write-Host "  Registrado." -ForegroundColor Green
}

Register-Hostname -Hostname $ApexDomain
Register-Hostname -Hostname $WwwHost

Show-HostnameStatus

Write-Host ""
Write-Host "=====================================================================" -ForegroundColor Yellow
Write-Host " Registros DNS a criar no provedor de $ApexDomain                     " -ForegroundColor Yellow
Write-Host "=====================================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "1) WWW (subdominio) — CNAME"
Write-Host "   Host / Name : www"
Write-Host "   Type        : CNAME"
Write-Host "   Value / Target : $defaultHostname"
Write-Host "   TTL         : 300 (ou default)"
Write-Host ""
Write-Host "2) APEX (raiz) — validacao TXT + trafego"
Write-Host "   a) TXT de validacao (obrigatorio no apex):"
Write-Host "      Host / Name : _dnsauth   (ou _dnsauth.$ApexDomain, conforme o provedor)"
Write-Host "      Type        : TXT"
Write-Host "      Value       : use o validationToken impresso acima para $ApexDomain"
Write-Host "      (Se o token ainda nao apareceu, rode: .\scripts\configure-site-domain.ps1 -Status)"
Write-Host ""
Write-Host "   b) Trafego para o SWA (escolha o que o provedor suportar):"
Write-Host "      - ALIAS / ANAME / CNAME flattening apontando para: $defaultHostname"
Write-Host "      - Ou registros A com os IPs publicados pela Microsoft para SWA apex"
Write-Host "        (docs: Set up a custom domain with Azure DNS / Free custom domains)"
Write-Host ""
Write-Host "3) Opcional: redirect www -> https://$ApexDomain no provedor DNS"
Write-Host "   (SWA Free nao faz redirect host-based nativo; o site responde nos dois hosts)."
Write-Host ""
Write-Host "Depois da propagacao DNS, rode de novo:"
Write-Host "  .\scripts\configure-site-domain.ps1 -Status"
Write-Host ""
Write-Host "Canonical do site ja aponta para https://$ApexDomain" -ForegroundColor Green
