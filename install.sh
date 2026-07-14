#!/usr/bin/env bash
#
# qa-expert-agent — instalador
# Instala o agente `qa-expert` e as 10 skills no opencode.
#
#   curl -fsSL https://raw.githubusercontent.com/emersinrp/qa-expert-agent/master/install.sh | bash
#
# Variáveis opcionais:
#   QA_EXPERT_BRANCH      branch a instalar (padrão: master)
#   OPENCODE_CONFIG_DIR   pasta de config do opencode (padrão: ~/.config/opencode)
#
set -euo pipefail

REPO="emersinrp/qa-expert-agent"
BRANCH="${QA_EXPERT_BRANCH:-master}"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
AGENTS_DIR="$CONFIG_DIR/agents"
SKILLS_DIR="$CONFIG_DIR/skills"

# cores (só se for terminal)
if [ -t 1 ]; then
  BOLD="$(printf '\033[1m')"; RED="$(printf '\033[31m')"; GREEN="$(printf '\033[32m')"
  DIM="$(printf '\033[2m')"; RESET="$(printf '\033[0m')"
else
  BOLD=""; RED=""; GREEN=""; DIM=""; RESET=""
fi

info()  { printf "%s\n" "$*"; }
ok()    { printf "%s✓%s %s\n" "$GREEN" "$RESET" "$*"; }
die()   { printf "%s✗ %s%s\n" "$RED" "$*" "$RESET" >&2; exit 1; }

printf "\n%sqa-expert%s — instalando agente + skills no opencode\n%s%s%s\n\n" \
  "$BOLD" "$RESET" "$DIM" "Qualidade é a base. Arquitetura é o teto. IA é a alavanca." "$RESET"

# dependências
command -v curl >/dev/null 2>&1 || die "curl não encontrado. Instale o curl e rode de novo."
command -v tar  >/dev/null 2>&1 || die "tar não encontrado. Instale o tar e rode de novo."

# download + extração num tmp que é limpo no final
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

info "→ baixando ${REPO} (${BRANCH})..."
curl -fsSL "https://codeload.github.com/${REPO}/tar.gz/refs/heads/${BRANCH}" \
  | tar -xz -C "$TMP" \
  || die "falha ao baixar/extrair o repositório. Verifique sua conexão."

SRC="$(find "$TMP" -maxdepth 1 -type d -name 'qa-expert-agent-*' | head -n1)"
[ -n "$SRC" ] && [ -f "$SRC/qa-expert.md" ] || die "pacote inválido: qa-expert.md não encontrado."

# backup de instalação anterior (se existir)
if [ -f "$AGENTS_DIR/qa-expert.md" ]; then
  cp "$AGENTS_DIR/qa-expert.md" "$AGENTS_DIR/qa-expert.md.bak"
  info "→ backup do agente anterior em ${AGENTS_DIR}/qa-expert.md.bak"
fi

# instala agente
mkdir -p "$AGENTS_DIR"
cp "$SRC/qa-expert.md" "$AGENTS_DIR/qa-expert.md"
ok "agente instalado em ${AGENTS_DIR}/qa-expert.md"

# instala skills
mkdir -p "$SKILLS_DIR"
cp -R "$SRC/skills/." "$SKILLS_DIR/"
SKILL_COUNT="$(find "$SKILLS_DIR" -name SKILL.md | wc -l | tr -d ' ')"
ok "${SKILL_COUNT} skills instaladas em ${SKILLS_DIR}/"

printf "\n%sPronto!%s Abra o opencode e peça uma tarefa de teste — o %sqa-expert%s despacha sozinho.\n" \
  "$GREEN" "$RESET" "$BOLD" "$RESET"
printf "%sEx.: \"escreve um teste E2E de login com Playwright\"%s\n\n" "$DIM" "$RESET"
