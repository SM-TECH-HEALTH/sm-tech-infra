#!/usr/bin/env bash
# Preserva o estado dos Container Apps (API e agents) antes de QUALQUER
# `azd provision` do ambiente compartilhado.
#
# Motivo: sm-tech-back, sm-tech-front e sm-tech-agents provisionam o MESMO
# main.bicep. O Bicep declara a imagem de cada Container App; sem repassar a
# imagem em uso, todo provision que muda algo volta a API/agents para o
# helloworld ate o pipeline do dono atualizar a imagem de novo. Alem disso,
# so o pipeline do sm-tech-agents liga DEPLOY_AI_AGENTS; se back/front
# provisionassem com o valor padrao (false), a API perderia a URL dos agentes
# (AgentesIa__UrlBase) e o chat publicado ficaria desligado.
#
# Este script:
#   - grava API_CONTAINER_IMAGE / AGENTS_CONTAINER_IMAGE com a imagem em uso;
#   - liga DEPLOY_AI_AGENTS quando o Container App dos agentes ja existe e o
#     pipeline nao definiu o valor.
#
# Uso: AZURE_ENV_NAME=dev ./scripts/ensure-container-apps-state.sh
# Deve rodar com working-directory na raiz deste repo, com o ambiente azd ja
# selecionado.
set -euo pipefail

imagem_atual() {
  az containerapp list \
    --query "[?tags.\"azd-env-name\"=='$AZURE_ENV_NAME' && tags.\"azd-service-name\"=='$1'].properties.template.containers[0].image | [0]" \
    -o tsv
}

API_IMAGE=$(imagem_atual api)
if [ -n "$API_IMAGE" ]; then
  azd env set API_CONTAINER_IMAGE "$API_IMAGE"
  echo "Imagem da API preservada: $API_IMAGE"
else
  echo "Container App da API ainda nao existe; provision usa a imagem inicial."
fi

AGENTS_IMAGE=$(imagem_atual agents)
if [ -n "$AGENTS_IMAGE" ]; then
  azd env set AGENTS_CONTAINER_IMAGE "$AGENTS_IMAGE"
  echo "Imagem dos agents preservada: $AGENTS_IMAGE"
  # `azd env get-value` de chave inexistente escreve erro no stdout (nao vem
  # vazio) — por isso le o valor por `get-values` e compara exatamente.
  DEPLOY_ATUAL=$(azd env get-values | sed -n 's/^DEPLOY_AI_AGENTS="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')
  if [ "$DEPLOY_ATUAL" != "true" ] && [ "$DEPLOY_ATUAL" != "false" ]; then
    azd env set DEPLOY_AI_AGENTS true
    echo "Container App dos agents existe; DEPLOY_AI_AGENTS=true neste provision."
  fi
else
  echo "Container App dos agents ainda nao existe; DEPLOY_AI_AGENTS segue o valor do pipeline."
fi
