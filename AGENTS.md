# Repository Guidelines

## Project Structure & Module Organization

This repository builds and launches a reusable Docker environment for coding agents. The root-level `Dockerfile` defines the toolchain. `agent` is the main host-side launcher; `agent-build` converts `versions.env` entries into Docker build arguments; and `agent-entrypoint` starts SSH before executing the requested command. `versions.env_example` documents supported version pins, while `versions.env` supplies the local build values. Keep user-facing behavior and setup instructions synchronized with `README.md`. Runtime state under `.codex/`, `.claude/`, `.config/opencode/`, and `.local/share/opencode/` is local and must remain untracked except for the shared instruction files explicitly allowed by `.gitignore`.

## Build, Test, and Development Commands

- `AI_AGENT_HOME="$PWD" ./agent-build` builds `agent-container:latest` from this checkout. Docker must be running.
- `AI_AGENT_HOME="$PWD" ./agent --help` checks launcher help and option documentation.
- `bash -n agent agent-build agent-entrypoint` performs fast syntax validation.
- `shellcheck agent agent-build agent-entrypoint` reports common shell errors.
- `AI_AGENT_HOME="$PWD" ./agent status` exercises workspace/container discovery after a build.

Override the image during experiments with `AI_AGENT_IMAGE=agent-container:dev` so the normal `latest` image is unaffected.

## Coding Style & Naming Conventions

Write portable, readable Bash while retaining the existing `#!/usr/bin/env bash` shebang and strict error handling. Quote expansions, use `[[ ... ]]` for tests, prefer descriptive uppercase names for environment-derived constants, and lowercase names for functions and locals. Indent nested shell blocks consistently with the surrounding file. Use uppercase underscore-separated Docker `ARG` and `ENV` names. Keep comments focused on intent and update command help whenever flags change.

## Testing Guidelines

There is currently no automated test framework or coverage threshold. Every shell change should pass `bash -n` and ShellCheck. For launcher or image changes, build the image and smoke-test the affected flow, such as `./agent`, `./agent status`, `./agent exec git status`, and `./agent stop`. Verify port-related changes with a non-default port to avoid local collisions.

## Commit & Pull Request Guidelines

The repository has no commits yet, so no established commit convention can be inferred. Start with short, imperative subjects such as `Add callback port validation`, keeping each commit focused. Pull requests should explain the behavior changed, list validation commands run, link relevant issues, and include representative terminal output when CLI messages or port mappings change. Call out version-pin and security-sensitive mount changes explicitly.

## Security & Configuration

Never commit agent credentials, SSH keys, or state directories. Treat Docker socket mounts, `--privileged`, and forwarded ports as elevated access; document why they are required and default to the narrowest permissions.
