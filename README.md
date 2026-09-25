# Agent Container

A reusable Docker-based development environment optimized for AI coding agents.

It provides a consistent toolchain for:

* OpenAI Codex
* Claude Code
* OpenCode
* Python
* Ruby
* Bundler
* Node.js / npm
* PowerShell
* Git
* GitHub CLI
* Ansible
* Minify
* Docker CLI
* SSH client and server
* native compilation
* debugging
* repository inspection
* networking
* shell/static-analysis utilities
* code formatters for the included language toolchains

The container can be launched from **any project directory** just by typing
`agent` in a terminal. The current directory is mounted as `/workspace`, while
AI-agent configuration and authentication state persist outside the disposable
container.

The final image size varies with the host platform and selected dependency
versions but is about 4 GB on my computer.

_Side note, this started as a simple setup. Then I used ChatGPT to vastly improve
it. And then I pointed this very agent-container at it's own repo and now look at it now.
It absolutely blew up in complexity and functionality. That is what I call recursive
improvement._

Extra side note: I have not tested the Windows or Claude functionality. It should work,
but I wouldn't be surprised if there are errors.

## Features

The image includes common coding-agent utilities such as:

```text
Python (managed by mise)
Ruby / Bundler (managed by mise)
Node.js / npm (managed by mise)
uv
PowerShell

shfmt (Bash and POSIX shell)
Ruff (Python)
Standard Ruby
Prettier (JavaScript, TypeScript, JSON, YAML, and Markdown)
PSScriptAnalyzer / Invoke-Formatter (PowerShell)
clang-format (C and C++)
cmake-format

Claude Code
OpenAI Codex
OpenCode

git
gh
curl
wget
jq
ripgrep
minify
find
file
tree
less
vim
micro

gcc
g++
make
cmake
ninja
pkg-config
autoconf
automake
libtool
patch

gdb
strace
lsof
shellcheck

openssh-client
openssh-server
iproute2
netcat-openbsd
dnsutils

zip
unzip
tar
gzip
xz
bzip2
rsync
sqlite3
ansible

Docker CLI
mise
```

Runtime versions are managed by `mise`. An optional `versions.env` file can
pin versions, request the latest release, or omit individual tools.

## Requirements

Install Docker Engine or Docker Desktop and make sure its daemon is running.
On Windows, Docker Desktop must be using Linux containers.

Linux and macOS hosts also need Bash, Git, and either `sha256sum` (common on
Linux) or `shasum` (included with macOS). Automatic SSH-port selection requires
one of `lsof`, `ss`, or `nc` on those hosts.

Windows hosts need Windows PowerShell 5.1 or PowerShell 7 and Git. The optional
`agent tunnel` command also needs the Windows OpenSSH Client feature; current
Windows installations normally include it.

## Installation

### macOS and Linux

Clone the repository into:

```bash
git clone https://github.com/magnusviri/agent-container.git ~/.agent-container
```

Note, installing it at ~/.agent-container makes it easier to to enable persistent auth
files and other things. This can be configured with environment variables (see below).

Make `agent` available from any directory with:

```bash
./agent init
```

This creates `agent` and `agent-container` symlinks in `~/.agent-container/bin`
and appends that directory to `PATH` in `~/.zshrc` when the file exists and the
entry is not already present. Restart your shell or run `source ~/.zshrc`, then
use `agent` anywhere. Run `./agent init` again to refresh the shortcuts.

Alternatively, add convenience symlinks manually:

```bash
mkdir -p ~/.local/bin
ln -sf ~/.agent-container/agent ~/.local/bin/agent
```

Ensure `~/.local/bin` is on your `PATH`.

For zsh, add it to `~/.zshrc` automatically:

```bash
grep -qxF "export PATH=\"\$HOME/.local/bin:\$PATH\"" ~/.zshrc 2>/dev/null || echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.zshrc
```

For Bash:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

You may want to place that in `~/.bashrc`.

### Windows installation

From PowerShell, clone the repository to the default state directory:

```powershell
git clone https://github.com/magnusviri/agent-container.git "$HOME\.agent-container"
```

The repository includes native PowerShell launchers and `.cmd` wrappers, so
Bash, WSL, and executable-bit changes are not required. Run them directly:

```powershell
& "$HOME\.agent-container\agent.cmd" build
& "$HOME\.agent-container\agent.cmd" --help
```

To use `agent` from any new PowerShell or Command Prompt window, add the
installation directory to your user `PATH` once:

```powershell
& "$HOME\.agent-container\agent.cmd" init
```

This adds the install directory to the user `PATH` (like the manual snippet
below) and prints confirmation. Open a new terminal afterward.

Or add it manually:

```powershell
$agentHome = "$HOME\.agent-container"
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $agentHome) {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$agentHome", 'User')
}
```

Then open a new terminal. Windows resolves `agent` to `agent.cmd`; its options
and commands match the Bash launcher. If Docker Desktop prompts to share the
drive or directory containing a workspace, approve that mount before launching
the container. The Windows launcher also compensates when Git checks the shared
instruction symlinks out as plain placeholder files, without modifying the
checkout.

## Building the image

Build the agent image with:

```bash
agent build
```

The same command works in PowerShell after the Windows installation above:

```powershell
agent build
```

Building first is optional. When a launch needs an image that does not exist,
`agent` offers to build it automatically. In a non-interactive session, run
`agent build` explicitly before launching.

The default image name is:

```text
agent-container:latest
```

Override it with:

```bash
AI_AGENT_IMAGE=my-agent:latest agent build
```

In PowerShell, environment-variable overrides use this syntax:

```powershell
$env:AI_AGENT_IMAGE = 'my-agent:latest'
agent build
```

## Basic usage

Move into any project:

```bash
cd ~/src/my-project
```

On Windows, use the same `agent` commands from PowerShell after changing to a
Windows project directory:

```powershell
Set-Location "$HOME\src\my-project"
```

Then launch an agent.

### Codex

```bash
agent codex
```

The launcher runs Codex with `--sandbox danger-full-access --no-daemon` by
default. The container provides the outer isolation boundary, and avoiding
Codex's managed background daemon prevents excessive host load from its
runtime activity on host-backed filesystems. Pass an explicit `--sandbox` (or
`-s`) option after `codex` to override the sandbox default.

The same default applies inside the container. Interactive container shells
define a `codex` wrapper, so typing `codex` in a shell behaves like
`agent codex`. Passing an explicit `--sandbox` option still overrides that
default. Use `command codex` if you deliberately need Codex's managed daemon.

When Codex requires browser authentication, start it with
`agent --forward-port 1455 codex`. See
[SSH port forwarding](#ssh-port-forwarding) for the full login flow. A normal
`agent codex` no longer starts an SSH server or publishes authentication ports.

### Claude Code

```bash
agent claude
```

The launcher runs Claude Code with `--dangerously-skip-permissions` by default
because the container provides the outer isolation boundary. Pass an explicit
`--permission-mode` option after `claude` to override this default.

Claude Code refuses that flag while running as root, so the launcher starts
every container with `IS_SANDBOX=1`, the environment variable that tells Claude
Code its surroundings are already sandboxed. The launcher then drops privileges
and runs Claude Code as the unprivileged `agent` user, so the flag is accepted.

The container shell applies the same default. Interactive container shells
define a `claude` wrapper, so typing `claude` in a shell behaves like
`agent claude`. Passing an explicit `--permission-mode` option still overrides
it.

### OpenCode

```bash
agent opencode
```

The launcher runs OpenCode with `--dangerously-skip-permissions` by default
because the container provides the outer isolation boundary. Pass an explicit
`--auto`, `--yolo`, or `--dangerously-skip-permissions` option after `opencode`
to override this default.

The same default applies inside the container. Interactive container shells
define an `opencode` wrapper, so typing `opencode` in a shell behaves like
`agent opencode`. Passing an explicit `--auto`, `--yolo`, or
`--dangerously-skip-permissions` option still overrides it.

### Ralph loop

Ralph runs one task at a time in a fresh Codex, Claude Code, or OpenCode
process. Code changes, the task queue, and a progress log carry context between
iterations; agent conversation history does not.

Authenticate the selected backend before leaving it unattended. Ralph reuses
the same persisted Codex, Claude Code, and OpenCode state as interactive agent
sessions; it does not perform an interactive login during the loop.

Initialize a project from the host:

```bash
agent ralph init
```

This creates missing files without replacing existing ones:

```text
AGENTS-RALPH.md          Ralph-only operating instructions
tasks.json               local task queue
progress.md              local progress and reusable learnings
```

The initializer adds `/tasks.json` and `/progress.md` to the project's
`.gitignore`. Commit `AGENTS-RALPH.md` when the project should share its
Ralph behavior.

Ask an agent to inspect the project and prepare the task queue before starting
the loop. The container instructions include the full schema and planning
rules. A suitable prompt is:

```text
Inspect this repository and create /workspace/tasks.json for Ralph to
implement: <describe the feature>. Follow the "Creating Ralph tasks.json"
instructions in /usr/local/share/agent-container/AGENTS.md. Do not
implement the tasks.
```

Then select a backend and optionally set the maximum number of iterations
(default 10):

```bash
agent ralph --tool codex
agent ralph --tool claude 20
agent ralph --tool opencode
```

If a matching container is already running, `agent ralph` executes there. If a
stopped container exists, the launcher starts and reuses it. Otherwise, the
launcher creates a reusable workspace container, runs Ralph inside it, and
stops it when the loop exits. The launcher then offers the normal choice to
keep or delete the stopped container.

From a shell already inside the container, use the same loop directly without
Docker:

```bash
ralph init
ralph --tool codex
ralph --tool claude 20
ralph --tool opencode
```

Every iteration starts a new non-interactive backend process and works on one
highest-priority story whose `passes` value is `false`. The loop succeeds only
after every story passes and the agent emits `<promise>COMPLETE</promise>`.

### Generic shell

```bash
agent
```

If no container is running for the current project, this starts a new container with Bash.

If a container is already running for that project, it attaches to the running container using:

```bash
docker exec -it --user agent --env HOME=/home/agent <container-id> bash
```

If a stopped container exists for the project, it is started automatically
instead of creating a new one. The container stays up while interactive
terminals are attached and is stopped once the last interactive terminal exits.
The launcher then asks whether to keep the stopped container for later reuse or
delete it. Keeping it is the default.

This makes it easy to open multiple terminals into the same agent environment.

## Workspace-specific containers

Containers are associated with the physical path of the current working directory.

For example:

```bash
cd ~/src/project-a
agent codex
```

creates a container associated with `project-a`.

From another terminal:

```bash
cd ~/src/project-a
agent
```

attaches to that same running container.

But:

```bash
cd ~/src/project-b
agent
```

uses a separate container.

The launcher calculates a stable workspace identifier from:

```bash
pwd -P
```

and labels the Docker container accordingly.

## Running commands in an existing container

Use:

```bash
agent exec COMMAND...
```

Commands run as the unprivileged `agent` user, including sessions opened from
a second terminal window.

For example:

```bash
agent exec git status
```

```bash
agent exec npm test
```

```bash
agent exec bundle exec rspec
```

```bash
agent exec python -m pytest
```

To open another Bash session:

```bash
agent exec bash
```

If no command follows `exec`, Bash is used automatically:

```bash
agent exec
```

This is equivalent to:

```bash
docker exec -it --user agent --env HOME=/home/agent <container-id> bash
```

For occasional system maintenance, run a command as root from the host:

```bash
agent root apt-get update
agent root apt-get install -y PACKAGE
```

Run `agent root` without a command to open an interactive root shell. This
privilege is provided by the host launcher through `docker exec`; no `sudo`
command or other privilege-escalation path is made available to the `agent`
user inside the container. The default setup does not mount the Docker socket,
so a coding agent cannot invoke this host-side capability from inside the
container.

## Container status

New containers use the workspace directory name plus the first 12 characters
of the absolute workspace path's SHA-256 hash. For `/home/me/project-a`, the
container is named `agent-project-a-<hash>` and its hostname is
`project-a-<hash>`. The directory name is lowercased, unsupported characters
are replaced with hyphens, and long names are shortened to keep the hostname
valid.

Check whether a container is running for the current workspace:

```bash
agent status
```

Example output for a normal shell (no ports published):

```text
Agent container is running:
  ID:       9f4723ab921d
  Name:     agent-project-a-f359abc71234
  Image:    agent-container:latest
  Status:   Up 12 minutes
  Ports:
```

When a container is created with `--forward-port`, the ports section shows its
SSH mapping, for example `127.0.0.1:2222->22/tcp`. Forwarded service ports
travel inside that SSH connection and are not published by Docker.

## Listing containers

List all running agent containers, including their IDs, names, images, statuses,
ports, and host workspace directories:

```bash
agent list
```

Example output:

```text
ID: 9f4723ab921d	Name: agent-project-a-f359abc71234	Image: agent-container:latest	Status: Up 12 minutes	Ports: 127.0.0.1:2222->22/tcp	PWD: /home/me/project-a
ID: 1a2b3c4d5e6f	Name: agent-project-b-7f8e9d012345	Image: agent-container:latest	Status: Up 3 minutes	Ports:	PWD: /home/me/project-b
```

## Stopping a container

Stop the agent container associated with the current project:

```bash
agent stop
```

When the last interactive terminal exits, the launcher asks whether to keep the
stopped container so you can inspect logs, reuse the filesystem, or restart it,
or delete it immediately. To remove a kept container for the current workspace
later, use `agent delete`.

Persistent AI-agent state is stored on the host and is not removed.

## Persistent agent state

The agent configuration and state directories are mounted into every agent
container.

Whenever a container starts, `agent-config-audit` checks `~/.config`,
`~/.claude`, and `~/.codex` and prints the mount boundaries whose contents
come from outside the container image. This includes the persistent agent state
mounts described below and optional nested credential mounts such as
`~/.config/gh`. The audit prints paths and mount sources, not file contents.

### Codex

```text
~/.agent-container/.codex
```

is mounted at:

```text
/home/agent/.codex
```

Its `AGENTS.md` is a symbolic link to the shared container instructions at
`/usr/local/share/agent-container/AGENTS.md`.

### Claude Code

```text
~/.agent-container/.claude
```

is mounted at:

```text
/home/agent/.claude
```

Its `CLAUDE.md` is a symbolic link to the shared container instructions at
`/usr/local/share/agent-container/AGENTS.md`.

By default Claude Code splits its state between `~/.claude` and a separate
`~/.claude.json` file in the home directory. That file holds the signed-in
account, the selected authentication method, and the completed-onboarding flag,
so leaving it outside the mount made Claude Code ask to authenticate again in
every new container.

The image therefore sets:

```dockerfile
ENV CLAUDE_CONFIG_DIR=/home/agent/.claude
```

which keeps `.claude.json` and `.credentials.json` together inside the mounted
directory, where both persist.

`~/.claude.json` is not mounted as a single file on purpose. Claude Code
rewrites it by writing a temporary file and renaming it over the original, and
that rename does not reach the host through a file bind mount.

### OpenCode

OpenCode's global configuration directory:

```text
~/.agent-container/.config/opencode
```

is mounted at:

```text
/home/agent/.config/opencode
```

Its `AGENTS.md` is a symbolic link to the shared container instructions at
`/usr/local/share/agent-container/AGENTS.md`.

OpenCode's application data directory:

```text
~/.agent-container/.local/share/opencode
```

is mounted at:

```text
/home/agent/.local/share/opencode
```

OpenCode stores authentication, logs, sessions, and other application data in
this second directory. These mount targets follow OpenCode's default Linux
locations; no path override is required.

This means authentication, preferences, and other agent state survive disposable containers.

It also means this works:

```bash
agent
```

and then from inside the shell:

```bash
codex
claude
opencode
```

All three tools still have access to their persistent state.

These directories can contain sensitive authentication material. Git tracks
only their shared instruction files and ignores all other contents.

The included `.gitignore` uses these rules:

```gitignore
.codex/*
!.codex/AGENTS.md
.claude/*
!.claude/CLAUDE.md
.config/opencode/*
!.config/opencode/AGENTS.md
.local/share/opencode/*
```

## Ports

No ports are published by default for a normal shell, Codex, Claude Code, or
OpenCode. When creating a container without any published ports, the launcher
asks for confirmation because ports cannot be added after the container is
created.

For example:

```bash
agent
```

```bash
agent claude
```

```bash
agent opencode
```

publish no ports unless explicitly requested (see below).

### SSH-forwarded ports

When running:

```bash
agent --forward-port 1455 codex
```

the launcher starts `sshd` and publishes its SSH endpoint:

```text
host 2222 -> container 22
```

The mapping binds to `127.0.0.1`, so it is reachable only from the Docker host.
The requested port is carried inside SSH rather than published by Docker.
`--forward-port` works with any command and can be repeated. See
[SSH port forwarding](#ssh-port-forwarding) below for more information.

## Opening custom ports

Publish application ports using `-p` or `--port`.

A single port:

```bash
agent -p 3000 claude
```

means:

```text
host 3000 -> container 3000
```

Multiple ports:

```bash
agent \
    -p 3000 \
    -p 5173 \
    -p 5432 \
    codex
```

Different host and container ports:

```bash
agent -p 8080:3000 opencode
```

means:

```text
host 8080 -> container 3000
```

You can also specify a bind address:

```bash
agent -p 127.0.0.1:3000:3000 claude
```

Binding development ports to `127.0.0.1` is recommended when they do not need
to be reachable from other machines. Without an explicit bind address, Docker
publishes the port on all host interfaces by default.

### Ports are fixed at container creation

Docker fixes published ports when a container is created. When `-p` is used for
an existing workspace container, the launcher starts or attaches to it only if
that mapping is already part of the container configuration. Otherwise it exits
and explains that the container must be deleted and recreated.

The launcher reports this instead of silently dropping the request. When a
container already exists for the workspace, delete it and start a new one:

```bash
agent delete
agent -p 3000 claude
```

Published ports are printed whenever a container is started, including when an
existing stopped container is restarted:

```text
Published ports:
  Port:  3000 -> container:3000
```

## Opt-in SSH and GitHub credentials

Host SSH and GitHub credentials are not shared with agent containers by
default. To share them with a newly created workspace container, point the
launcher at a home-style credential profile:

```bash
agent --credentials "$HOME/.agent-credentials/work" codex
```

The launcher recognizes these directories within the selected profile:

```text
~/.agent-credentials/work/
├── .ssh/       -> /home/agent/.ssh
└── .config/
    └── gh/     -> /home/agent/.config/gh
```

Either directory may be omitted, but the profile must contain at least one of
them. Other files in the profile, including `.gitconfig` and
`.git-credentials`, are not mounted. The launcher does not create missing
credential directories.

The `--credentials` mounts are read-write so SSH can update `known_hosts` and
GitHub CLI can update its authentication state. Use read-only mounts when the
container should not modify the selected profile:

```bash
agent --credentials-ro "$HOME/.agent-credentials/personal" claude
```

With read-only mounts, operations such as adding an SSH host key, running
`gh auth login`, or refreshing stored authentication may fail. Existing SSH
keys and GitHub CLI authentication remain usable when the tools do not need to
write.

Different containers can select different profiles:

```bash
cd ~/src/company-project
agent --credentials "$HOME/.agent-credentials/work" codex

cd ~/src/personal-project
agent --credentials-ro "$HOME/.agent-credentials/personal" claude
```

Docker fixes bind mounts when a container is created. If a container is already
running for the workspace, stop it before relaunching with a credential option.
The `exec`, `status`, and `stop` commands do not accept credential options.

Once a workspace container was explicitly created with a profile, later
`agent` and `agent exec` sessions attached to that same container can access
the mounted credentials until the container is stopped.

## Example workflow

Build the environment:

```bash
agent build
```

Open a project:

```bash
cd ~/src/my-app
```

Start Codex:

```bash
agent codex
```

From another terminal:

```bash
cd ~/src/my-app
agent
```

This opens another Bash shell in the same running container.

Run tests from a third terminal:

```bash
cd ~/src/my-app
agent exec npm test
```

Inspect Git:

```bash
agent exec git status
```

Check the container:

```bash
agent status
```

Stop it:

```bash
agent stop
```

Delete it when you are done:

```bash
agent delete
```

## Directory layout

The default installation location is:

```text
~/.agent-container/
├── Dockerfile
├── versions.env_example
├── versions.env (optional)
├── agent
├── agent.cmd
├── agent.ps1
├── agent-entrypoint
├── agent-config-audit
├── ralph
├── AGENTS-CONTAINER.md
├── README.md
├── LICENSE
├── .gitignore
│
├── .codex/
│   └── AGENTS.md -> /usr/local/share/agent-container/AGENTS.md
├── .claude/
│   └── CLAUDE.md -> /usr/local/share/agent-container/AGENTS.md
├── AGENTS-RALPH.md
├── .config/
│   └── opencode/
│       └── AGENTS.md -> /usr/local/share/agent-container/AGENTS.md
└── .local/
    └── share/
        └── opencode/ (runtime data, created automatically)
```

The agent configuration directories are managed by Git so they can provide the
same instructions to each tool. The canonical file is installed in the image
at `/usr/local/share/agent-container/AGENTS.md`; Codex's `AGENTS.md`, Claude
Code's `CLAUDE.md`, and OpenCode's `AGENTS.md` are symbolic links to it. All
other configuration and runtime files in these directories are ignored.

Codex's `app-server-control` directory is mounted as container-local temporary
storage. Its Unix socket is therefore not placed on the host-backed `.codex`
state mount, while credentials and the rest of the Codex configuration remain
persistent. The control directory is recreated when the container starts.

## Version configuration

The Dockerfile installs the latest version of each configurable language runtime
and coding agent by default. Language runtimes and Terraform are installed with
`mise`. Every tool setting accepts an exact version, `latest`, or an empty value.
An empty value omits that tool from the image. Terraform is omitted by default;
set `TERRAFORM_VERSION` to an exact version or `latest` to install it. Debian
remains a required base image and continues to use its configured image tag. You
do not need a `versions.env` file unless you want to pin, update, or omit one or
more tools.

This project is intended to make it easy to tailor and build an agent image
locally for your own environment. It is not intended to produce Docker images
for sharing: the default use of `latest` and the ability to select local tool
versions prioritize customization over reproducible distribution.

To create an override file, copy the provided example:

```bash
cp ~/.agent-container/versions.env_example ~/.agent-container/versions.env
```

Then uncomment and change only the settings you want to override. Commented or
omitted settings continue to use the Dockerfile defaults. For example, pin
Codex to a specific version:

```dotenv
CODEX_VERSION=0.147.0
```

Request the latest version explicitly:

```dotenv
CODEX_VERSION=latest
```

Or omit a tool entirely:

```dotenv
OPENCODE_VERSION=
```

To install Terraform, set its version explicitly or request the latest release:

```dotenv
TERRAFORM_VERSION=latest
```

Using `latest` makes builds less stable because the installed version can
change whenever a new release is published. Rebuild without the Docker cache to
ensure the newest release is installed:

```bash
agent build --no-cache
```

The `versions.env` file is intentionally ignored by Git. Delete it to return to
the Dockerfile defaults, which install the latest version of every configurable
tool.

After changing an exact-version override, rebuild the image normally:

```bash
agent build
```

## Repository safety

Because host-mounted repositories can have ownership that differs from the user inside the container, the image configures Git with:

```bash
git config --system --add safe.directory '*'
```

This avoids Git's `dubious ownership` error in mounted workspaces.

Only use this configuration in an environment where mounting arbitrary untrusted repositories is acceptable.

## Non-root user

The container runs an unprivileged `agent` user instead of `root`. The
interactive shell and the `codex`, `claude`, and `opencode` commands all run as
`agent`, whose home directory is `/home/agent`. Their persistent state lives
under `/home/agent` rather than `/root`.

The launcher also passes `--user agent` whenever it opens another session in
an existing container. Use the explicit host-side `agent root [COMMAND...]`
maintenance command only when root access is needed.

This keeps `/root` and other system locations out of reach of the coding
agents. The tools can still read and write everything under `/workspace`
(eventually) and their own state under `/home/agent`.

Only the optional `sshd` daemon runs as `root`; it is started when
`--forward-port` is used because binding the SSH service and managing logins
require those privileges. The SSH login itself runs as `agent`, and root login
over SSH is disabled.

## Security notes

This container is intended as an AI coding-agent sandbox, but it is not automatically a strong security boundary.

AI coding agents can execute shell commands and modify files available to the container.

Be especially careful when exposing:

```text
Docker socket
SSH credentials
API credentials
cloud credentials
production databases
Kubernetes credentials
host filesystem paths
```

The `--credentials` and `--credentials-ro` options deliberately expose the
selected SSH and GitHub CLI credentials to every process in that workspace
container. Use a narrowly scoped profile for each agent or trust boundary, and
stop the container when access is no longer needed.

The default setup intentionally avoids mounting the Docker socket.

Persistent agent state may contain sensitive tokens. Keep these directories private:

```text
~/.agent-container/.codex
~/.agent-container/.claude
~/.agent-container/.config/opencode
~/.agent-container/.local/share/opencode
```

Only the shared instruction files in these directories are managed by Git; all
other contents are ignored.

## SSH port forwarding

Some command-line services authenticate in a browser and redirect it to a
listener on `localhost` inside the container. `--forward-port` creates a
generic SSH tunnel for that callback; it is not tied to Codex.

### Codex example

When Codex first starts it displays this message.

```
  Welcome to Codex, OpenAI's command-line coding agent

  Sign in with ChatGPT to use Codex as part of your paid plan
  or connect an API key for usage-based billing

> 1. Sign in with ChatGPT
     Usage included with Plus, Pro, Business, and Enterprise plans

  2. Sign in with Device Code
     Sign in from another device with a one-time code

  3. Provide your own API key
     Pay for what you use
```

Choosing "Sign in with ChatGPT" displays a link to open in a web browser. After
sign-in, the browser redirects to localhost port 1455. Start Codex with that
port forwarded:

```bash
agent --forward-port 1455 codex
```

The container starts `sshd` whenever `--forward-port` is present. The password
and the command to run on your computer are printed when the container starts.
You might have to scroll because the service can clear the screen.

```
SSH:   localhost:2222 -> container:22

============================================================
 SSH credentials (randomly generated)
------------------------------------------------------------
 User:      agent
 Password:  j2zWKDiDmkw6fWamemvoIb4iaGaQju9HF25nVuGZKAc
 Host port: 2222
============================================================

Run this command in another terminal on your computer:

  ssh -N -p 2222 -L 1455:localhost:1455 agent@localhost

             _._:=++==+,_
         _=,/*\+/+\=||=_ _"+_
       ,|*|+**"^`   `"*`"~=~||+
      ;*_\*',,_            /*|;|,
     \^;/'^|\`\\            ".|\\,
    ~* +`  |*/;||,           '.\||,
   +^"-*    '\|*/"|_          ! |/|
   ||_|`     ,//|;|*            "`|
   |=~'`    ;||^\|".~++++++_+, =" |
    _~;*  _;+` /* |"|___.:,,,|/,/,|
    \^_"^ ^\,./`   `^*''* ^*"/,;_/
     *^, ", `              ,'/*_|
       ^\,`\+_          _=_+|_+"
         ^*,\_!*+:;=;;.=*+_,|*
           `*"*|~~___,_;+*"


  Welcome to Codex, OpenAI's command-line coding agent

  Sign in with ChatGPT to use Codex as part of your paid plan
  or connect an API key for usage-based billing
```

Run the printed command in another terminal on the Docker host, enter the
printed password, and leave it running while completing browser authentication.

Instead of copying the printed command, you can run this on the Docker host:

```bash
agent tunnel
```

This finds the running workspace container, reads its configured forwarded
ports, removes any saved host key for the discovered SSH port, and opens the
tunnel. It exits with an error if the container has no configured forwards.

If the tunnel reports a changed host key, `agent tunnel` automatically
removes the saved key for the discovered SSH port before connecting. If you
need to reset it manually, use the SSH port mapped to container port 22 (for
example, `2222`):

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
```

Then reset the saved key and try the tunnel again.

```bash
ssh-keygen -R "[localhost]:<ssh-port>"
```

SSH host keys are generated during the image build, so containers created from
one image share an SSH server identity. Rebuilding the image without its cached
SSH-key layer can generate a new identity.

Codex credentials persist in `~/.agent-container/.codex`. Once authentication
is complete, later sessions can normally use `agent codex` without a forward.

## Custom SSH port

Specify the desired host SSH port:

```bash
agent --ssh-port 2200 --forward-port 1455 codex
```

This maps:

```text
host 2200 -> container 22
```

You can also set:

```bash
export AI_AGENT_SSH_PORT=2200
```

## Forwarding other ports

The short form uses the same port on your computer and in the container:

```bash
agent --forward-port 1455 codex
```

Use `LOCAL:CONTAINER` when the two ports should differ:

```bash
agent --forward-port 8080:3000 some-command
```

The option can be repeated for a service that needs more than one port:

```bash
agent --forward-port 8000 --forward-port 9000 some-command
```

The equivalent environment setting supports one forward:

```bash
export AI_AGENT_FORWARD_PORT=1455
agent codex
```

Without `--forward-port` or `AI_AGENT_FORWARD_PORT`, `sshd` is not started.

## Docker access

The image contains the Docker CLI, but the host Docker socket is intentionally
**not mounted by default**.

If an agent needs to control the host Docker daemon:

```bash
agent \
    --docker-arg \
    --volume=/var/run/docker.sock:/var/run/docker.sock \
    claude
```

Access to the Docker socket effectively provides highly privileged access to the host.

Only enable it when needed.

## Passing arbitrary Docker arguments

Use:

```bash
--docker-arg
```

For example:

```bash
agent \
    --docker-arg --privileged \
    codex
```

Multiple arguments can be supplied:

```bash
agent \
    --docker-arg --cap-add=SYS_PTRACE \
    --docker-arg --security-opt=seccomp=unconfined \
    claude
```

## Verbose logging

Use `-v` or `--verbose` to see every Docker command the launcher runs:

```bash
agent --verbose -p 3000 claude
```

Each command is printed to stderr, quoted so it can be copied and rerun
directly:

```text
+ docker ps --filter label=agent-container=true --filter label=agent-workspace=63d66b2564f5 --format {{.ID}}
# workspace:      /home/me/project
# container name: agent-project-63d66b2564f5
# hostname:       project-63d66b2564f5
# image:          agent-container:latest
# requested ports: 3000
Port:  3000 -> container:3000
+ docker run --interactive --tty --init --name agent-project-63d66b2564f5 --hostname project-63d66b2564f5 ... --publish 3000:3000 agent-container:latest claude
```

This is the quickest way to confirm which `--publish` flags reached
`docker run`, and whether the launcher created a container at all or reused an
existing one.

Set `AI_AGENT_VERBOSE=1` to enable the same output without passing the flag.

## Environment variables

### `AI_AGENT_HOME`

Controls where configuration and persistent state live.

Default:

```text
~/.agent-container
```

Example:

```bash
export AI_AGENT_HOME="$HOME/my-agent"
```

### `AI_AGENT_IMAGE`

Controls the Docker image.

Default:

```text
agent-container:latest
```

Example:

```bash
export AI_AGENT_IMAGE=my-company-agent:latest
```

### `AI_AGENT_SSH_PORT`

Sets the preferred host SSH port when forwarding is enabled.

Example:

```bash
export AI_AGENT_SSH_PORT=2222
```

### `AI_AGENT_FORWARD_PORT`

Configures one SSH-forwarded port in `PORT` or `LOCAL:CONTAINER` form.

Example:

```bash
export AI_AGENT_FORWARD_PORT=1455
```

### `AI_AGENT_VERBOSE`

Set to `1` to log every Docker command the launcher runs, the same as passing
`--verbose`.

Example:

```bash
export AI_AGENT_VERBOSE=1
```

## License

This project is licensed under the [MIT License](LICENSE).
