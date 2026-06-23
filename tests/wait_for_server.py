#!/usr/bin/env python3
import argparse
import json
import sys
import time
from pathlib import Path

import requests


def render_response(response: requests.Response) -> str:
    content_type = response.headers.get("content-type", "")
    if "application/json" in content_type:
        try:
            return json.dumps(response.json(), indent=2, ensure_ascii=False)
        except ValueError:
            pass
    return response.text[:2000]


def main() -> int:
    parser = argparse.ArgumentParser(description="Wait for llama-server to become ready.")
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--interval", type=float, default=5.0)
    parser.add_argument("--log-file", default="/content/llama-server.log")
    args = parser.parse_args()

    base_url = args.base_url.rstrip("/")
    health_url = f"{base_url}/health"
    models_url = f"{base_url}/v1/models"
    deadline = time.time() + args.timeout
    last_status = None

    print(f"Waiting for llama-server: {health_url}")
    while time.time() < deadline:
        try:
            response = requests.get(health_url, timeout=10)
            body = render_response(response)
            last_status = f"GET /health -> HTTP {response.status_code}: {body}"

            if response.status_code == 200:
                print(last_status)
                models = requests.get(models_url, timeout=20)
                print(f"GET /v1/models -> HTTP {models.status_code}")
                print(render_response(models))
                return 0

            print(last_status)
        except requests.RequestException as exc:
            last_status = f"{type(exc).__name__}: {exc}"
            print(last_status)

        time.sleep(args.interval)

    print("FAIL: llama-server did not become ready before timeout.")
    if last_status:
        print(f"Last status: {last_status}")

    log_path = Path(args.log_file)
    if log_path.exists():
        print(f"\nLast 120 lines of {log_path}:")
        lines = log_path.read_text(errors="replace").splitlines()
        print("\n".join(lines[-120:]))

    return 1


if __name__ == "__main__":
    sys.exit(main())
