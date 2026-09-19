# Repository agent guidance

## Configuration map

`AGENTS.md` is guidance for coding agents working in this repository.

| File | Controls | Edit when |
|------|----------|-----------|
| `.env.example` | The committed template for runtime secrets and API keys. | You add a provider/model that needs a new key, or introduce another non-secret runtime value. Copy it to `.env` locally; never commit `.env`. |
| `docker-compose.yml` | Service definitions, ports, mounted config files, and environment variables passed to services. | You add a service, change ports/volumes, or expose a new `.env` key to LiteLLM or OpenWebUI. |
| `config/litellm/config.yaml` | LiteLLM's model list and general gateway behavior. This is the source for models exposed through `http://localhost:4000/v1`. | You add, remove, rename, or reroute a model, or change LiteLLM logging/model storage settings. Restart LiteLLM after edits. |
| `config/codex/config.toml` | The committed, minimal Codex CLI configuration: its selected model/provider and connection to LiteLLM. | You change Codex defaults or LiteLLM connection settings. It is copied to `~/.codex/config.toml` only during first-time install; the installer never overwrites an existing user config. |
| `.gitignore` | Repository-level ignored paths, notably `.env`. | You introduce another generated/local artifact that should not be committed. |
| `install.sh` | First-run setup and stack startup. It creates `.env`, validates keys, installs the Codex config non-destructively, and starts Docker Compose. | You add setup, validation, or startup behavior that affects users during installation. |
| `README.md` | User-facing quick start, architecture, URLs, and high-level configuration summary. | User-visible setup, service names, ports, or configuration workflows change. Keep implementation details in this file or inline docs. |

### Editing rules

- Secrets and real API keys belong only in the uncommitted `.env`; put placeholder values in `.env.example`.
- A new key must be added in three places: `.env.example`, the relevant service `environment` mapping in `docker-compose.yml`, and `os.environ/<KEY>` in the consuming config.
- `docker-compose.yml` mounts `config/litellm/config.yaml` as `/app/config.yaml` at container creation. If the container already exists, recreate the LiteLLM service after editing a mounted config: `docker compose up -d --force-recreate litellm` (or restart if the implementation supports reload; recreate is the safe default).
- Keep model aliases useful for humans, especially when the underlying provider path is verbose.

## Adding OpenRouter models through LiteLLM

OpenRouter model IDs use the public `vendor/model` form, for example `z-ai/glm-5.3-flash` or `qwen/qwen3-coder-plus`.

To expose one through LiteLLM, append an entry under `model_list` in `config/litellm/config.yaml`:

```yaml
  - model_name: my-model-alias
    litellm_params:
      model: openrouter/<vendor>/<model>
      custom_llm_provider: openrouter
      api_key: os.environ/OPENROUTER_API_KEY
      drop_params: true
      additional_drop_params:
        - reasoning
```

- `model_name` is the name clients call through LiteLLM and see in OpenWebUI. Choose a short alias, such as `qwen-coder`.
- `model` must be `openrouter/` followed by the exact OpenRouter model ID.
- `custom_llm_provider` must remain `openrouter`.
- `api_key` resolves `OPENROUTER_API_KEY` from the stack environment. Verify that key exists in `.env`; no edit to `docker-compose.yml` is needed for an additional OpenRouter model.
- `additional_drop_params: [reasoning]` strips the OpenAI Responses-style `reasoning` parameter, which some OpenRouter endpoints reject. Include parameters only when needed for that model.

Then restart/recreate the LiteLLM service and confirm the model is registered:

```bash
docker compose up -d --force-recreate litellm
curl -sS http://localhost:4000/v1/models \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}"
```

When adding a model as a Codex default, update `model` in `config/codex/config.toml` using the same `model_name` from the LiteLLM config. OpenWebUI discovers LiteLLM's model list, so no separate model declaration is required there.

To launch Codex with a configured LiteLLM model without changing the default, pass the exact `model_name` from `config/litellm/config.yaml`:

```bash
codex -m z-ai/glm-5.3-flash
```

The `-m`/`--model` value must exactly match the LiteLLM `model_name`, including any slash-separated provider prefix. Ensure `LITELLM_API_KEY` is set before launching; if omitted, Codex falls back to the `model` default configured in `config/codex/config.toml`.
