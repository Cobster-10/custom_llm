#!/usr/bin/env python3
import argparse
import json
import os
import sys
from typing import Any

import requests


def pretty(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True)


def print_probe(base_url: str, headers: dict[str, str]) -> None:
    root_url = base_url.rstrip("/").removesuffix("/v1")
    probe_urls = [
        root_url,
        root_url + "/health",
        root_url + "/v1/models",
    ]

    print("\nEndpoint probe:")
    for url in probe_urls:
        try:
            response = requests.get(url, headers=headers, timeout=20)
            print(f"GET {url} -> HTTP {response.status_code}")
            if response.text:
                print(response.text[:2000])
        except requests.RequestException as exc:
            print(f"GET {url} -> {type(exc).__name__}: {exc}")


def main() -> int:
    default_model_repo = os.environ.get(
        "MODEL_REPO", "HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive"
    )
    default_model_quant = os.environ.get("MODEL_QUANT", "Q8_K_P")
    default_model = os.environ.get("MODEL_ID", f"{default_model_repo}:{default_model_quant}")

    parser = argparse.ArgumentParser(
        description="Check whether an OpenAI-compatible endpoint returns structured tool_calls."
    )
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:8080/v1",
        help="OpenAI-compatible API base URL, for example http://127.0.0.1:8080/v1",
    )
    parser.add_argument(
        "--model",
        default=default_model,
        help="Model id to send in the chat completion request.",
    )
    parser.add_argument("--api-key", default="not-needed")
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()

    url = args.base_url.rstrip("/") + "/chat/completions"
    headers = {
        "Authorization": f"Bearer {args.api_key}",
        "Content-Type": "application/json",
    }

    payload = {
        "model": args.model,
        "messages": [
            {
                "role": "system",
                "content": (
                    "You are connected to tools. When the user asks for weather, "
                    "call the get_weather tool. Do not answer in prose."
                ),
            },
            {
                "role": "user",
                "content": "Use the weather tool for Chicago, Illinois.",
            },
        ],
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": "get_weather",
                    "description": "Get current weather for a city.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "city": {
                                "type": "string",
                                "description": "City and region, for example Chicago, Illinois.",
                            },
                            "unit": {
                                "type": "string",
                                "enum": ["fahrenheit", "celsius"],
                            },
                        },
                        "required": ["city"],
                        "additionalProperties": False,
                    },
                },
            }
        ],
        "tool_choice": "auto",
        "temperature": 0.2,
        "top_p": 0.8,
        "max_tokens": 512,
    }

    print(f"POST {url}")
    response = requests.post(url, headers=headers, json=payload, timeout=args.timeout)
    print(f"HTTP {response.status_code}")
    print(f"Content-Type: {response.headers.get('content-type', '<missing>')}")

    try:
        data = response.json()
    except ValueError:
        if response.text:
            print(response.text[:4000])
        else:
            print("<empty response body>")
        print_probe(args.base_url, headers)
        return 1

    print(pretty(data))

    if response.status_code >= 400:
        print_probe(args.base_url, headers)
        return 1

    try:
        choice = data["choices"][0]
        message = choice["message"]
    except (KeyError, IndexError, TypeError):
        print("FAIL: response does not look like an OpenAI chat completion.")
        return 1

    tool_calls = message.get("tool_calls")
    finish_reason = choice.get("finish_reason")

    if not tool_calls:
        print("FAIL: response did not include message.tool_calls.")
        return 1

    if finish_reason != "tool_calls":
        print(f"FAIL: finish_reason was {finish_reason!r}, expected 'tool_calls'.")
        return 1

    first = tool_calls[0]
    function = first.get("function", {})
    name = function.get("name")
    arguments = function.get("arguments")

    if name != "get_weather":
        print(f"FAIL: first tool call name was {name!r}, expected 'get_weather'.")
        return 1

    try:
        parsed_args = json.loads(arguments or "{}")
    except json.JSONDecodeError:
        print(f"FAIL: tool arguments are not valid JSON: {arguments!r}")
        return 1

    if "city" not in parsed_args:
        print(f"FAIL: tool arguments missing city: {parsed_args!r}")
        return 1

    print("PASS: endpoint returned a structured OpenAI-style tool call.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
