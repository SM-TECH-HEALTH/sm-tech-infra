#!/usr/bin/env bash
# Reafirma a connection string do Postgres externo de dev (Supabase) antes de
# QUALQUER `azd provision` do ambiente compartilhado dev.
#
# Motivo: sm-tech-back, sm-tech-front e sm-tech-agents provisionam o MESMO
# Container App da API (main.bicep compartilhado). Só o pipeline do
# sm-tech-back tem o secret DEV_DATABASE_CONNECTION_STRING. Quando front ou
# agents provisionam, esse parametro chega vazio e o Bicep tenta gravar o
# secret 'connection-string' vazio no Container App — a validacao da Azure
# rejeita isso (ContainerAppSecretInvalid: value or keyVaultUrl and identity
# should be provided), derrubando o provision inteiro.
#
# Se o pipeline atual ja tem DEV_DATABASE_CONNECTION_STRING (hoje, so o
# sm-tech-back), este script nao faz nada. Caso contrario, reaproveita o
# valor ja gravado no Container App em producao via `az containerapp secret
# show --show-values` (a mesma identidade do pipeline ja tem permissao,
# pois ela atualiza a imagem do Container App nos passos seguintes).
#
# Uso: AZURE_ENV_NAME=dev ./scripts/ensure-dev-database-secret.sh
set -euo pipefail

if [ -n "${DEV_DATABASE_CONNECTION_STRING:-}" ]; then
  echo "DEV_DATABASE_CONNECTION_STRING ja fornecido por este pipeline; nada a reafirmar."
  exit 0
fi

API_JSON=$(az containerapp list --query "[?tags.\"azd-env-name\"=='$AZURE_ENV_NAME' && tags.\"azd-service-name\"=='api'] | [0]" -o json)
API_NAME=$(echo "$API_JSON" | jq -r '.name // empty')
API_RG=$(echo "$API_JSON" | jq -r '.resourceGroup // empty')

if [ -z "$API_NAME" ]; then
  echo "Container App da API do ambiente '$AZURE_ENV_NAME' ainda nao existe; provision seguira sem connection string de dev (primeiro provision precisa vir de um pipeline com o secret, hoje o sm-tech-back)."
  exit 0
fi

EXISTING_CONN=$(az containerapp secret show \
  --name "$API_NAME" --resource-group "$API_RG" \
  --secret-name connection-string --show-values --query value -o tsv 2>/dev/null || true)

if [ -n "$EXISTING_CONN" ] && [ "$EXISTING_CONN" != "None" ]; then
  azd env set DEV_DATABASE_CONNECTION_STRING "$EXISTING_CONN"
  echo "Connection string de dev reaproveitada do Container App ja provisionado ($API_NAME)."
else
  echo "Nao foi possivel ler a connection string atual da API; provision seguira sem ela (secret pode ficar invalido nesta rodada)."
fi
