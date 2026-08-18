# AGENTS.md — sm-tech-infra

Infraestrutura Azure do SM-TECH: Bicep, Container Apps, PostgreSQL Flexible Server, Static Web Apps, OIDC GitHub.

Antes de editar, leia:

- [`../sm-tech-ai/AGENTS.md`](../sm-tech-ai/AGENTS.md)
- `docs/passo-a-passo-setup.md`
- `docs/github-azure-setup.md`

Código: `infra/main.bicep`, `infra/modules/`, workflows em `.github/workflows/`.

Não aplique padrões de tela SMT nem Clean Architecture de API aqui. Mudanças de arquitetura de nuvem que afetem o produto → ADR em `../sm-tech-ai/specs/architecture/adr/` e skill `atualizar-referencias`.

Não commite secrets de Azure no repo. Git: `develop` → feature → PR `develop`; produção só `release/*` → `main` ([`../sm-tech-ai/specs/git.md`](../sm-tech-ai/specs/git.md)). Alerta de risco obrigatório antes do PR.
