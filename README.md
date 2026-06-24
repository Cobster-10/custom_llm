# custom_llm

Serve an open-source GGUF model as an OpenAI-compatible API for OpenClaw.

The success condition is not just "the model responds." OpenClaw needs real structured tool calls:

```text
choices[0].message.tool_calls
choices[0].finish_reason == "tool_calls"
```

## Target Model

Verified Thunder model:

```text
HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:Q4_K_M
```

Default runtime settings:

```text
PORT=8080
CTX_SIZE=4096
N_GPU_LAYERS=99
PARALLEL=1
```

`Q4_K_M` is the first verified Thunder configuration for structured tool calls. `Q8_K_P` downloads on an A100 80 GB instance, but still needs loading/runtime tuning before it should be treated as the default.

## Thunder Compute Flow

Recommended starting instance:

```text
GPU: 1x A100 80 GB
Mode: development
vCPUs: 4
Disk: 200 GB
Template: cuda12-8
```

After the instance is running:

```bash
nvidia-smi
git clone https://github.com/Cobster-10/custom_llm.git
cd custom_llm
bash scripts/setup_gpu_server.sh
bash scripts/start_llama_server.sh
python3 tests/wait_for_server.py --base-url http://127.0.0.1:8080
python3 tests/test_tool_call.py --base-url http://127.0.0.1:8080/v1
```

Only after the structured tool-call test passes, expose the server:

```bash
bash scripts/start_cloudflare_tunnel.sh
cat ~/custom_llm_runtime/openclaw_base_url.txt
```

Use that printed `https://.../v1` endpoint as OpenClaw's OpenAI-compatible base URL.

## Runtime Files

On a normal GPU VM, runtime files default to:

```text
~/custom_llm_runtime
```

Override with `RUNTIME_DIR` if needed:

```bash
RUNTIME_DIR=/data/custom_llm_runtime bash scripts/setup_gpu_server.sh
```

The setup defaults `CMAKE_CUDA_ARCHITECTURES=80`, which targets the A100. Override it only if you switch to a different GPU family.

## Important Files

- `AGENTS.md` - project context for coding agents.
- `config/model.env.example` - model and runtime knobs.
- `scripts/setup_gpu_server.sh` - installs/builds llama.cpp CUDA server and downloads cloudflared.
- `scripts/start_llama_server.sh` - starts native `llama-server` with `--jinja`.
- `scripts/start_cloudflare_tunnel.sh` - exposes the local server through a Cloudflare quick tunnel.
- `tests/wait_for_server.py` - checks whether the server is ready.
- `tests/test_tool_call.py` - verifies OpenAI-style structured tool calls.

## Notes

- Do not debug OpenClaw until `tests/test_tool_call.py` passes against the raw endpoint.
- A 404 from `/v1/chat/completions` does not by itself prove the model failed. Check `/health`, `/v1/models`, process ownership of port `8080`, and the llama-server log.
- Keep downloaded models, logs, runtime builds, tunnel files, and temporary SSH/debug files out of Git.
