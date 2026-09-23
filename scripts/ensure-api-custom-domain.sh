#!/usr/bin/env bash
# Reafirma os dominios customizados da API (api-demo.smtechsistemas.com.br) e
# dos agentes (agentes-demo.smtechsistemas.com.br) antes
# de QUALQUER `azd provision` do ambiente compartilhado.
#
# Motivo: o Container App da API, o Static Web App do front e o Container App
# dos agents nascem do mesmo main.bicep/resource group. Os pipelines de
# sm-tech-back, sm-tech-front e sm-tech-agents rodam `azd provision`
# independentemente, e o Bicep declara o ingress da API por inteiro
# (container-apps.bicep) a partir dos parametros apiCustomDomainName /
# apiCustomDomainCertificateId. Se QUALQUER um desses pipelines provisionar
# sem repassar esses parametros, o Bicep reseta o ingress e o binding do
# dominio custom some (o certificado gerenciado em si sobrevive, so o binding
# no Container App e que e resetado). Por isso este script roda nos 3
# pipelines, sempre logo antes de `azd provision`.
#
# Uso:
#   AZURE_ENV_NAME=dev ./scripts/ensure-api-custom-domain.sh
# Deve rodar com working-directory apontando para a raiz deste repo (onde
# `azd env` consegue resolver o ambiente ja selecionado).
set -euo pipefail

API_CUSTOM_DOMAIN_HOSTNAME="api-demo.smtechsistemas.com.br"
AGENTS_CUSTOM_DOMAIN_HOSTNAME="agentes-demo.smtechsistemas.com.br"

CAE_JSON=$(az containerapp env list --query "[?tags.\"azd-env-name\"=='$AZURE_ENV_NAME'] | [0]" -o json)
CAE_NAME=$(echo "$CAE_JSON" | jq -r '.name // empty')
CAE_RG=$(echo "$CAE_JSON" | jq -r '.resourceGroup // empty')

if [ -z "$CAE_NAME" ]; then
  echo "Container Apps Environment do ambiente '$AZURE_ENV_NAME' ainda nao existe; provision seguira sem dominio custom."
  exit 0
fi

# reafirmar_dominio <hostname> <VAR_NOME> <VAR_CERTIFICADO>
reafirmar_dominio() {
  local hostname="$1" var_nome="$2" var_cert="$3" cert_id
  cert_id=$(az containerapp env certificate list \
    --name "$CAE_NAME" --resource-group "$CAE_RG" \
    --query "[?properties.subjectName=='$hostname'].id | [0]" -o tsv)

  if [ -n "$cert_id" ] && [ "$cert_id" != "None" ]; then
    azd env set "$var_nome" "$hostname"
    azd env set "$var_cert" "$cert_id"
    echo "Dominio customizado reafirmado: $hostname -> $cert_id"
  else
    echo "Certificado gerenciado para $hostname nao encontrado ainda; provision seguira sem esse dominio custom."
  fi
}

reafirmar_dominio "$API_CUSTOM_DOMAIN_HOSTNAME" API_CUSTOM_DOMAIN_NAME API_CUSTOM_DOMAIN_CERTIFICATE_ID
# Agentes (sm-tech-agents): mesmo problema — o ingress do Container App dos
# agents tambem e declarado inteiro no Bicep (agents-app.bicep).
reafirmar_dominio "$AGENTS_CUSTOM_DOMAIN_HOSTNAME" AGENTS_CUSTOM_DOMAIN_NAME AGENTS_CUSTOM_DOMAIN_CERTIFICATE_ID
