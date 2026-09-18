#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_URL="https://github.com/asaini/openmodelstack.git"

# If the compose file isn't in the current directory, we're probably being
# run standalone (e.g. curl | bash). Clone the repo first.
if [ ! -f "${SCRIPT_DIR}/docker-compose.yml" ]; then
  INSTALL_DIR="${HOME}/.openmodelstack"
  if [ -d "${INSTALL_DIR}" ]; then
    echo "Existing install found at ${INSTALL_DIR} — pulling latest..."
    git -C "${INSTALL_DIR}" pull --ff-only
  else
    echo "Cloning repo to ${INSTALL_DIR}..."
    git clone "${REPO_URL}" "${INSTALL_DIR}"
  fi
  SCRIPT_DIR="${INSTALL_DIR}"
fi

ENV_FILE="${SCRIPT_DIR}/.env"
CODEX_CONFIG_DIR="${HOME}/.codex"
CODEX_CONFIG_FILE="${CODEX_CONFIG_DIR}/config.toml"

echo "=== Intelligence Stack Installer ==="
echo ""

# 1. Check prerequisites
if ! command -v docker &>/dev/null; then
  echo "Error: Docker is not installed. Install it from https://docs.docker.com/get-docker/"
  exit 1
fi

if ! docker compose version &>/dev/null; then
  echo "Error: Docker Compose v2 is required."
  exit 1
fi

# 2. Set up .env
if [ -f "${ENV_FILE}" ]; then
  echo ".env already exists — skipping setup."
else
  cp "${SCRIPT_DIR}/.env.example" "${ENV_FILE}"
  echo "Created .env from template."
  echo ""
  echo "Please edit .env with your API keys before continuing:"
  echo "  ${ENV_FILE}"
  echo ""
  read -r -p "Press Enter after editing .env (or Ctrl+C to exit now)..."
fi

# 3. Source .env for key checking
set -a
source "${ENV_FILE}"
set +a

for var in POSTGRES_PASSWORD LITELLM_MASTER_KEY WEBUI_SECRET_KEY; do
  if [[ "${!var:-}" == replace-with* ]]; then
    echo ""
    echo "Warning: ${var} is still set to the template default."
    read -r -p "Generate a random value for ${var}? [Y/n] " gen
    if [[ "${gen:-Y}" != "n" ]]; then
      local_val=$(openssl rand -hex 32)
      sed -i.bak "s|^${var}=.*|${var}=${local_val}|" "${ENV_FILE}"
      rm "${ENV_FILE}.bak"
      echo "Generated ${var}."
    fi
  fi
done

for var in FIREWORKS_API_KEY OPENAI_API_KEY OPENROUTER_API_KEY; do
  if [[ "${!var:-}" == *replace-with* ]]; then
    echo ""
    echo "Warning: ${var} is still a placeholder."
    read -r -p "Enter value for ${var} (or press Enter to skip): " keyval
    if [ -n "${keyval}" ]; then
      sed -i.bak "s|^${var}=.*|${var}=${keyval}|" "${ENV_FILE}"
      rm "${ENV_FILE}.bak"
    fi
    unset keyval
  fi
done

# Re-source after updates
set -a
source "${ENV_FILE}"
set +a

# 4. Install Codex config (non-destructive: only write if not present)
echo ""
if [ -f "${CODEX_CONFIG_FILE}" ]; then
  echo "Codex config already exists at ${CODEX_CONFIG_FILE} — not overwriting."
  echo "If you want to use this stack's Codex config, merge the model_provider"
  echo "settings from ${SCRIPT_DIR}/config/codex/config.toml manually."
else
  mkdir -p "${CODEX_CONFIG_DIR}"
  cp "${SCRIPT_DIR}/config/codex/config.toml" "${CODEX_CONFIG_FILE}"
  echo "Installed Codex config to ${CODEX_CONFIG_FILE}."
fi

echo ""
echo "Set LITELLM_API_KEY in your shell profile (e.g. ~/.zshrc):"
echo "  export LITELLM_API_KEY=\"\${LITELLM_MASTER_KEY}\""
echo ""

# 5. Start services
echo "Starting services..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yml" up -d

echo ""
echo "=== Stack is running ==="
echo ""
echo "  OpenWebUI:   http://localhost:3000"
echo "  LiteLLM API: http://localhost:4000/v1"
echo "  LiteLLM UI:  http://localhost:4000/ui"
echo ""
echo "LiteLLM master key is in .env (LITELLM_MASTER_KEY)."
echo "Use it as the API key for OpenWebUI and Codex."
