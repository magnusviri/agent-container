# Global execution environment

## Container sandboxing

- This coding environment already runs inside a Linux container whose outer
  runtime does not permit nested user or mount namespace creation.
- Do not invoke `bwrap` or `bubblewrap`, either directly or through helper
  commands known to require Bubblewrap.
- Do not repeatedly retry a command after it fails because Bubblewrap cannot
  create a namespace.
- When a managed file-editing helper fails specifically because it requires
  Bubblewrap, use a native Unix editing or patching utility that does not create
  another sandbox. Keep edits scoped to the requested files and preserve
  unrelated changes.
- Continue to honor the container's existing filesystem and approval
  boundaries. Request approval when an operation requires access beyond those
  boundaries; do not weaken the container or run it with `--privileged`.

## Container limitations

- The Docker CLI is installed, but no Docker daemon or host Docker socket is
  available by default. Commands such as `docker build`, `docker run`, and
  `docker compose up` therefore cannot work. Do not repeatedly retry them after
  confirming that the daemon is unavailable. Building images or managing
  containers requires the user to recreate or start this container with an
  explicitly mounted Docker socket or access to a remote Docker daemon.
- Do not try to start a nested Docker daemon. This container does not have the
  privileges, kernel access, or supported sandboxing needed for Docker-in-Docker.
- `systemd` is not the container's init system, so `systemctl` and services that
  require a full system boot are unavailable. When appropriate, run a service
  directly in the foreground or with its own supported development command.
- Only paths mounted into the container are durable and visible on the host.
  Work under `/workspace` for repository changes. Changes elsewhere in the
  container, including installed packages and system configuration, disappear
  when the disposable container is removed unless the path is an explicit
  persistent mount.
- The container cannot read arbitrary host files or access host devices. If a
  required path, socket, credential, or device was not mounted when the
  container started, report that limitation; it cannot be added from inside the
  running container.
- Host port publishing is fixed when the container is created. A process can
  listen on a container port, but making a new port reachable from the host
  requires restarting the container with the corresponding launcher `-p`
  option.
- Operations that require elevated kernel capabilities, such as mounting
  filesystems or attaching a debugger to some unrelated processes, may be
  denied. Do not attempt to bypass those boundaries; report when a task requires
  capabilities that the container was not granted.

## Available tools

- Languages, shells, and package managers: Bash, Python with `pip`, Ruby with
  `gem` and Bundler, Node.js with `npm`, and PowerShell. Runtime versions are
  managed by `mise`; `uv` is also available for Python package and environment
  management.
- Coding agents: OpenAI Codex, Claude Code, and OpenCode.
- Source control: Git and the GitHub CLI (`gh`).
- Formatters: `shfmt` for Bash and POSIX shell; Ruff for Python; Standard Ruby
  (`standardrb`) for Ruby; Prettier for JavaScript, TypeScript, JSON, YAML, and
  Markdown; PSScriptAnalyzer's `Invoke-Formatter` for PowerShell;
  `clang-format` for C and C++; and `cmake-format` for CMake.
- Search, transformation, and data processing: `rg`, `find`, `jq`, `minify`,
  `file`, `diff`, and SQLite (`sqlite3`).
- Build toolchain: `build-essential`, GCC, G++, Make, CMake, Ninja,
  `pkg-config`, Autoconf, Automake, Libtool, and `patch`. Development headers
  are installed for OpenSSL, libffi, zlib, bzip2, Readline, SQLite, ncurses,
  xz/lzma, gdbm, and YAML.
- Debugging and analysis: GDB, `strace`, `lsof`, and ShellCheck.
- Network and remote access: `curl`, `wget`, OpenSSH client and server, `ip`,
  `ss`, `nc`, and DNS utilities such as `dig`, `host`, and `nslookup`.
- Archives and file transfer: `tar`, `gzip`, `zip`, `unzip`, `xz`, `bzip2`, and
  `rsync`.
- Automation and container utilities: Ansible, the Docker CLI, and `gosu`. The
  Docker CLI can reach a Docker daemon only when a socket or remote daemon is
  explicitly made available to the container.
- General system and command-line utilities: GNU coreutils, findutils,
  diffutils, util-linux, procps, passwd utilities, CA certificates, locales,
  `less`, and `tree`.

## Creating Ralph tasks.json

Ralph reads its work queue from `/workspace/tasks.json`. Users can ask any of
the installed coding agents to inspect the current project and create this file
before starting the loop.

Use this prompt, replacing the placeholder with the desired feature:

```text
Inspect this repository and create /workspace/tasks.json for Ralph to
implement: <describe the feature>. Follow the "Creating Ralph tasks.json"
instructions in /usr/local/share/agent-container/AGENTS.md. Do not
implement the tasks.
```

The file must use this shape:

```json
{
  "branchName": "ralph/short-feature-name",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add the first capability",
      "description": "Describe the user-visible outcome and relevant context.",
      "acceptanceCriteria": [
        "State an observable requirement",
        "Name the relevant automated checks that must pass"
      ],
      "priority": 1,
      "passes": false
    }
  ]
}
```

When creating the file:

- Inspect the repository first so stories reflect its existing architecture,
  conventions, and test commands.
- Break the goal into stories small enough for one fresh-context iteration.
- Put prerequisite stories before dependent stories and use lower priority
  numbers for earlier work.
- Use unique sequential IDs and concrete, verifiable acceptance criteria.
- Include relevant type checking, linting, tests, and UI verification in the
  acceptance criteria.
- Set every `passes` value to `false`; only the Ralph implementation loop marks
  verified stories complete.
- Write valid JSON directly to `/workspace/tasks.json`. Do not implement any
  story while preparing the task file.

From outside the container, start `agent codex`, `agent claude`, or
`agent opencode` and submit the prompt. From an existing container shell, start
the corresponding `codex`, `claude`, or `opencode` command and submit it there.

## Host access

- To reach a service running on the container host, use the DNS name
  `host.docker.internal` rather than `localhost`. The launcher maps this name to
  Docker's host gateway.
