#!/usr/bin/env bash
# `azd provision` com retry curto para tolerar corrida entre pipelines.
#
# sm-tech-back, sm-tech-front e sm-tech-agents provisionam o MESMO resource
# group (main.bicep compartilhado) em pipelines independentes. Quando dois
# desses workflows disparam perto um do outro (ex: dois PRs mergeados em
# repos diferentes na mesma janela), o ARM pode recusar o segundo provision
# com "ContainerAppOperationInProgress" / "conflicting state" porque o
# primeiro ainda esta atualizando o Container App. Isso nao e um erro de
# config: e so o segundo provision chegando cedo demais. Tenta de novo com
# backoff antes de desistir.
#
# Uso: ./scripts/azd-provision-with-retry.sh
set -euo pipefail

MAX_ATTEMPTS=4
SLEEP_SECONDS=30

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  if OUTPUT=$(azd provision --no-prompt 2>&1); then
    echo "$OUTPUT"
    exit 0
  fi

  echo "$OUTPUT"

  if [ "$attempt" -eq "$MAX_ATTEMPTS" ]; then
    echo "azd provision falhou apos $MAX_ATTEMPTS tentativas."
    exit 1
  fi

  if echo "$OUTPUT" | grep -qiE "ContainerAppOperationInProgress|conflicting state|already exists or is in a conflicting state"; then
    echo "Conflito de provisionamento concorrente (tentativa $attempt/$MAX_ATTEMPTS). Aguardando ${SLEEP_SECONDS}s..."
    sleep "$SLEEP_SECONDS"
  else
    echo "azd provision falhou com erro nao relacionado a concorrencia; abortando sem retry."
    exit 1
  fi
done
