#!/usr/bin/env python3

import argparse
import json
import re
import ssl
import sys
import urllib.request
import urllib.error


def get_models(url, timeout=10, insecure=False):
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    context = None
    if insecure:
        context = ssl._create_unverified_context()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=context) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.reason}") from e
    except urllib.error.URLError as e:
        if isinstance(e.reason, ssl.SSLCertVerificationError):
            raise RuntimeError(
                f"Could not reach {url}: {e.reason}. "
                "The server certificate could not be verified; if this is a "
                "trusted endpoint, retry with --insecure."
            ) from e
        raise RuntimeError(f"Could not reach {url}: {e.reason}") from e
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Invalid JSON response: {e}") from e


def extract_models(data):
    entries = data.get("data")
    if entries is None:
        entries = data.get("models", [])
    if isinstance(entries, dict):
        return entries

    result = {}
    for model in entries:
        model_id = model.get("id") if isinstance(model, dict) else model
        if model_id:
            result[model_id] = {"name": model_id}
    return result


def derive_base_url(url):
    """Derive the provider baseURL from a /models endpoint URL."""
    return re.sub(r"/models/?$", "", url)


def build_config(data, provider_key, provider_npm, provider_name, base_url):
    models = extract_models(data)
    if not models:
        raise ValueError("No models found at the endpoint")

    return {
        "$schema": "https://opencode.ai/config.json",
        "provider": {
            provider_key: {
                "npm": provider_npm,
                "name": provider_name,
                "options": {
                    "baseURL": base_url,
                },
                "models": models,
            }
        },
        "model": f"{provider_key}/YOUR-MODEL-ID",
    }


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Fetch models from an OpenAI-compatible API and print an opencode provider block."
    )
    parser.add_argument(
        "url",
        help="Full /models endpoint URL, e.g. http://host.docker.internal:1234/v1/models",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=10,
        help="Request timeout in seconds (default: %(default)s)",
    )
    parser.add_argument(
        "--insecure",
        action="store_true",
        help="Skip TLS certificate verification (use only for trusted hosts "
        "such as local proxies with self-signed certificates)",
    )
    parser.add_argument(
        "--provider",
        default="lmstudio",
        help="Provider key in the opencode config (default: %(default)s)",
    )
    parser.add_argument(
        "--npm",
        default="@ai-sdk/openai-compatible",
        help="AI SDK npm package for the provider (default: %(default)s)",
    )
    parser.add_argument(
        "--name",
        default="LM Studio (Docker)",
        help="Human-readable provider name (default: %(default)s)",
    )
    parser.add_argument(
        "--base-url",
        help="Override the provider baseURL; by default it is inferred from the /models URL",
    )
    args = parser.parse_args(argv)

    url = args.url
    if not re.match(r"^https?://", url):
        print(
            f"Error: Invalid URL '{url}'. Expected the full /models endpoint, "
            "e.g. http://host.docker.internal:1234/v1/models",
            file=sys.stderr,
        )
        return 1

    base_url = args.base_url if args.base_url else derive_base_url(url)

    result = None
    try:
        data = get_models(url, args.timeout, args.insecure)
        result = build_config(
            data,
            args.provider,
            args.npm,
            args.name,
            base_url,
        )
    except (RuntimeError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
