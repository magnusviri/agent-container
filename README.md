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
* Git
* GitHub CLI
* Docker CLI
* SSH client and server
* native compilation
* debugging
* repository inspection
* networking
* shell/static-analysis utilities

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

## Features

The image includes common coding-agent utilities such as:

```text
Python
Ruby
Bundler
Node.js
npm

Claude Code
OpenAI Codex
OpenCode

git
gh
curl
wget
jq
ripgrep
find
file
tree
less

gcc
g++
make
cmake
ninja
pkg-config

gdb
strace
lsof
shellcheck

openssh-client
openssh-server
iproute2
netcat
dnsutils

zip
unzip
tar
gzip
xz
rsync
sqlite3

Docker CLI
```

Runtime versions are managed by `mise` and pinned by default in the
`Dockerfile`. An optional `versions.env` file can override those defaults.

## Requirements

Install Docker Engine or Docker Desktop and make sure its daemon is running.
The host also needs Bash, Git, and either `sha256sum` (common on Linux) or
`shasum` (included with macOS). Automatic SSH-port selection also requires one
of `lsof`, `ss`, or `nc` on the host.

## Installation

Clone the repository into:

```bash
git clone https://github.com/magnusviri/agent-container.git ~/.agent-container
```

Note, installing it at ~/.agent-container makes it easier to to enable persistent auth
files and other things. This can be configured with environment variables (see below).

Make the scripts executable:

```bash
chmod +x \
    ~/.agent-container/agent \
    ~/.agent-container/agent-build \
    ~/.agent-container/agent-entrypoint
```

Optionally add convenience symlinks:

```bash
mkdir -p ~/.local/bin

ln -sf ~/.agent-container/agent ~/.local/bin/agent
ln -sf ~/.agent-container/agent-build ~/.local/bin/agent-build
```

Ensure `~/.local/bin` is on your `PATH`.

For Bash:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

You may want to place that in `~/.bashrc`.

## Building the image

Build the agent image with:

```bash
agent-build
```

The default image name is:

```text
agent-container:latest
```

Override it with:

```bash
AI_AGENT_IMAGE=my-agent:latest agent-build
```

## Basic usage

Move into any project:

```bash
cd ~/src/my-project
```

Then launch an agent.

### Codex

```bash
agent codex
```

The launcher runs Codex with `--sandbox danger-full-access` by default because
the container provides the outer isolation boundary. Pass an explicit
`--sandbox` (or `-s`) option after `codex` to override this default.

When Codex requires authentication, select the ChatGPT sign-in option and open
the URL it displays. The launcher maps the callback listener to
`127.0.0.1:1455` on the host, so the browser can complete a normal local login.
See [Codex authentication](#codex-authentication) for the port and SSH-tunnel
details.

### Claude Code

```bash
agent claude
```

### OpenCode

```bash
agent opencode
```

### Generic shell

```bash
agent
```

If no container is running for the current project, this starts a new container with Bash.

If a container is already running for that project, it attaches to the running container using:

```bash
docker exec -it <container-id> bash
```

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
docker exec -it <container-id> bash
```

## Container status

Check whether a container is running for the current workspace:

```bash
agent status
```

Example output:

```text
Agent container is running:
  ID:       9f4723ab921d
  Name:     agent-f359abc71234
  Image:    agent-container:latest
  Status:   Up 12 minutes
  Ports:    127.0.0.1:2222->22/tcp, 127.0.0.1:1455->1455/tcp
```

## Stopping a container

Stop the agent container associated with the current project:

```bash
agent stop
```

The containers use `--rm`, so Docker removes the container after it exits.

Persistent AI-agent state is stored on the host and is not removed.

## Persistent agent state

The agent configuration and state directories are mounted into every agent
container.

### Codex

```text
~/.agent-container/.codex
```

is mounted at:

```text
/root/.codex
```

The repository-managed `AGENTS.md` in this directory contains the shared
container instructions.

### Claude Code

```text
~/.agent-container/.claude
```

is mounted at:

```text
/root/.claude
```

Its `CLAUDE.md` is a symbolic link to `.codex/AGENTS.md`.

### OpenCode

OpenCode's global configuration directory:

```text
~/.agent-container/.config/opencode
```

is mounted at:

```text
/root/.config/opencode
```

Its `AGENTS.md` is a symbolic link to `../../.codex/AGENTS.md`.

OpenCode's application data directory:

```text
~/.agent-container/.local/share/opencode
```

is mounted at:

```text
/root/.local/share/opencode
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

No ports are published by default for a normal shell, Claude Code, or OpenCode.

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

### Codex ports

When running:

```bash
agent codex
```

the launcher automatically starts `sshd` and publishes ports when
`~/.agent-container/.codex/auth.json` does not exist:

```text
host 2222 -> container 22
host 1455 -> container 1455
```

Both automatic mappings bind to `127.0.0.1`, so they are reachable only from
the Docker host. Pass `--no-codex-auth` to disable this behavior. See
[Codex authentication](#codex-authentication) below for more information.

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
├── .ssh/       -> /root/.ssh
└── .config/
    └── gh/     -> /root/.config/gh
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
agent-build
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

## Directory layout

The default installation location is:

```text
~/.agent-container/
├── Dockerfile
├── versions.env_example
├── versions.env (optional)
├── agent
├── agent-build
├── agent-entrypoint
├── README.md
├── LICENSE
├── .gitignore
│
├── .codex/
│   └── AGENTS.md
├── .claude/
│   └── CLAUDE.md -> ../.codex/AGENTS.md
├── .config/
│   └── opencode/
│       └── AGENTS.md -> ../../.codex/AGENTS.md
└── .local/
    └── share/
        └── opencode/ (runtime data, created automatically)
```

The agent configuration directories are managed by Git so they can provide the
same instructions to each tool. `.codex/AGENTS.md` is the canonical file;
Claude Code's `CLAUDE.md` and OpenCode's `AGENTS.md` are relative symbolic
links to it. All other configuration and runtime files in these directories are
ignored.

## Version configuration

The versions of Debian, the language runtimes, and the coding agents are pinned
in the `Dockerfile`. These pins reduce version drift between builds, although
the mutable Debian image tag and unpinned operating-system packages mean builds
are not fully reproducible. You do not need a `versions.env` file unless you
want to override one or more defaults.

To create an override file, copy the provided example:

```bash
cp ~/.agent-container/versions.env_example ~/.agent-container/versions.env
```

Then uncomment and change only the versions you want to override. Commented or
omitted settings continue to use the versions pinned in the `Dockerfile`. For
example:

```dotenv
CODEX_VERSION=0.147.0
```

Many of the tools also accept `latest` instead of a specific version:

```dotenv
CODEX_VERSION=latest
```

Using `latest` makes builds less stable because the installed version can
change whenever a new release is published. For that reason, the `Dockerfile`
pins every version by default. If you choose `latest`, rebuild without the
Docker cache to ensure the newest release is installed:

```bash
agent-build --no-cache
```

The `versions.env` file is intentionally ignored by Git. Delete it to return to
all of the versions pinned in the `Dockerfile`.

After changing an exact-version override, rebuild the image normally:

```bash
agent-build
```

## Repository safety

Because host-mounted repositories can have ownership that differs from the root user inside the container, the image configures Git with:

```bash
git config --system --add safe.directory '*'
```

This avoids Git's `dubious ownership` error in mounted workspaces.

Only use this configuration in an environment where mounting arbitrary untrusted repositories is acceptable.

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

## Codex authentication

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

I don't have a Device Code or API key, but I can sign in with ChatGPT. If I choose "Sign
in with ChatGPT", it displays a link to open in my web browser. After opening the page
and singing in, it tries to open localhost:1455, which goes nowhere. To fix that, I
needed to use ssh tunneling. This is how it works.

The container starts `sshd` when the container is launched with `agent codex` and
`~/.agent-container/.codex/auth.json` does not exist. Passing `--no-codex-auth`, prevents
`sshd` from starting.

The password for the tunnel is random and printed when the container starts. You might
have to scroll the Terminal window because codex clears the screen.

```
SSH:   localhost:2222 -> container:22
Codex: localhost:1455 -> container:1455

============================================================
 SSH credentials (randomly generated)
------------------------------------------------------------
 User:     root
 Password: j2zWKDiDmkw6fWamemvoIb4iaGaQju9HF25nVuGZKAc
 Port:     22
============================================================


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

Then, in another terminal, use the SSH port printed by the launcher (2222 in
this example):

```bash
ssh -p 2222 -L 1455:localhost:1455 root@localhost
```

If it says the key has changed:

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
```

Then reset the saved key and try the tunnel again.

```bash
ssh-keygen -R "[localhost]:2222"
```

SSH host keys are generated during the image build, so containers created from
one image share an SSH server identity. Rebuilding the image without its cached
SSH-key layer can generate a new identity.

Credentials persist in `~/.agent-container/.codex`. On later runs the launcher
detects `auth.json`, does not publish either authentication port, and does not
start `sshd`.

## Custom SSH port

Specify the desired host SSH port:

```bash
agent --ssh-port 2200 codex
```

This maps:

```text
host 2200 -> container 22
```

You can also set:

```bash
export AI_AGENT_SSH_PORT=2200
```

## Custom Codex callback port

The default host callback port is:

```text
1455
```

Override it with:

```bash
agent --codex-port 1456 codex
```

or:

```bash
export AI_AGENT_CODEX_PORT=1456
```

The container-side port remains `1455`.

Because Codex redirects the browser to local port 1455, changing the host port
is mainly useful when reserving port 1455 for the SSH-tunnel method described
above.

## Disable Codex authentication support

Disable the SSH endpoint, callback port, and `sshd` startup:

```bash
agent --no-codex-auth codex
```

This is also the automatic behavior when
`~/.agent-container/.codex/auth.json` exists.

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

Sets the preferred host SSH port for Codex mode.

Example:

```bash
export AI_AGENT_SSH_PORT=2222
```

### `AI_AGENT_CODEX_PORT`

Sets the host-side Codex callback port.

Default:

```text
1455
```

Example:

```bash
export AI_AGENT_CODEX_PORT=1456
```

## License

This project is licensed under the [MIT License](LICENSE).
