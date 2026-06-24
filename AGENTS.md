# Agent Context

## Goal

Run an open-source GGUF model as an OpenAI-compatible API for OpenClaw, with working OpenAI-style tool/function calling. OpenClaw expects structured `message.tool_calls` and `finish_reason: "tool_calls"`, not text that merely resembles a function call.

## Model And Serving Direction

Target model:

```text
HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive
```

Preferred serving approach:

```text
native llama.cpp llama-server + --jinja
```

Avoid returning to `python -m llama_cpp.server` unless there is a strong reason; earlier troubleshooting suggested it was producing malformed tool-call behavior for OpenClaw.

## Important Files

- `README.md` - human-facing project overview and run flow.
- `scripts/setup_gpu_server.sh` - Thunder/VM setup script that installs build tools, builds native CUDA `llama-server`, and downloads `cloudflared`.
- `scripts/start_llama_server.sh` - starts `llama-server` with `--jinja`, `--alias`, cleanup of stale port `8080` processes, and log output.
- `scripts/start_cloudflare_tunnel.sh` - starts Cloudflare quick tunnel and writes the OpenClaw base URL under the runtime directory.
- `tests/wait_for_server.py` - readiness checker for `/health`, `/v1/health`, and `/v1/models`.
- `tests/test_tool_call.py` - conformance test for OpenAI structured tool calls.
- `config/model.env.example` - model/runtime knobs.

## What Has Been Tried

- Original Colab workflow used `llama_cpp.server`; tool calling appeared malformed for OpenClaw.
- Switched to native `llama-server` with `--jinja`.
- Added a raw tool-call conformance test to isolate serving problems from OpenClaw config problems.
- Colab browser and VS Code Colab both proved unstable. VS Code showed disposed-session/websocket errors.
- A `pip install --upgrade requests` step broke Colab's expected `requests==2.32.4`; removed all pip upgrades.
- Full `git clone` of `llama.cpp` appeared to destabilize the Colab runtime; setup now downloads the llama.cpp release tarball instead.
- `tmate` debug shell worked and confirmed repo/scripts existed inside Colab, but the runtime/session died during the heavy llama.cpp clone path.

## Current Strategy

Use Thunder Compute with roughly 80GB VRAM. Prefer a single A100 80GB development-mode/prototyping instance for the first pass because it is available and cheaper than production mode.

On a rented GPU box, first verify:

```bash
nvidia-smi
git clone https://github.com/Cobster-10/custom_llm.git
cd custom_llm
bash scripts/setup_gpu_server.sh
bash scripts/start_llama_server.sh
python tests/wait_for_server.py --base-url http://127.0.0.1:8080
python tests/test_tool_call.py --base-url http://127.0.0.1:8080/v1
```

Only connect OpenClaw after `tests/test_tool_call.py` reports a structured OpenAI-style tool call.

## Cautions

- Do not assume a 404 from `/v1/chat/completions` means the model failed; check `/health`, `/v1/models`, logs, and whether the wrong/stale process owns port `8080`.
- Do not debug OpenClaw until the raw OpenAI-compatible endpoint passes the tool-call conformance test.
- Keep generated runtime artifacts, downloaded models, logs, and temporary SSH known-host files out of Git.
