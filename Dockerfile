# syntax=docker/dockerfile:1

ARG DEBIAN_VERSION=bookworm-slim
FROM debian:${DEBIAN_VERSION}

ARG PYTHON_VERSION=3.14.6
ARG RUBY_VERSION=3.4.10
ARG NODE_VERSION=24.18.1
ARG BUNDLER_VERSION=4.0.17
ARG CLAUDE_CODE_VERSION=2.1.220
ARG CODEX_VERSION=0.147.0
ARG OPENCODE_VERSION=1.18.4

ENV PYTHON_VERSION=${PYTHON_VERSION} \
    RUBY_VERSION=${RUBY_VERSION} \
    NODE_VERSION=${NODE_VERSION} \
    BUNDLER_VERSION=${BUNDLER_VERSION} \
    CLAUDE_CODE_VERSION=${CLAUDE_CODE_VERSION} \
    CODEX_VERSION=${CODEX_VERSION} \
    OPENCODE_VERSION=${OPENCODE_VERSION}

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false \
    NPM_CONFIG_AUDIT=false \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CONFIG_DIR=/home/agent/.claude \
    MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CONFIG_DIR=/etc/mise \
    PATH=/usr/local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    passwd \
    coreutils \
    findutils \
    diffutils \
    util-linux \
    procps \
    file \
    less \
    tree \
    locales \
    git \
    gh \
    gosu \
    ripgrep \
    jq \
    minify \
    curl \
    wget \
    openssh-client \
    openssh-server \
    iproute2 \
    netcat-openbsd \
    dnsutils \
    tar \
    gzip \
    zip \
    unzip \
    xz-utils \
    bzip2 \
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    ninja-build \
    pkg-config \
    autoconf \
    automake \
    libtool \
    patch \
    libssl-dev \
    libffi-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncurses-dev \
    liblzma-dev \
    libgdbm-dev \
    libyaml-dev \
    gdb \
    strace \
    lsof \
    shellcheck \
    sqlite3 \
    rsync \
    ansible \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    . /etc/os-release; \
    wget -q "https://packages.microsoft.com/config/debian/${VERSION_ID}/packages-microsoft-prod.deb" \
        -O /tmp/packages-microsoft-prod.deb; \
    dpkg -i /tmp/packages-microsoft-prod.deb; \
    rm /tmp/packages-microsoft-prod.deb; \
    apt-get update; \
    apt-get install -y --no-install-recommends powershell; \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://mise.run | sh \
    && install -m 0755 /root/.local/bin/mise /usr/local/bin/mise \
    && rm -rf /root/.local

RUN mise install --system \
        python@${PYTHON_VERSION} \
        ruby@${RUBY_VERSION} \
        node@${NODE_VERSION} \
    && mise use -g \
        python@${PYTHON_VERSION} \
        ruby@${RUBY_VERSION} \
        node@${NODE_VERSION} \
    && mise reshim \
    && python --version \
    && ruby --version \
    && node --version \
    && gem --version \
    && gem install bundler -v "${BUNDLER_VERSION}" --no-document \
    && mise reshim \
    && bundle --version

RUN npm install --global \
      @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION} \
      @openai/codex@${CODEX_VERSION} \
      opencode-ai@${OPENCODE_VERSION}

RUN curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh \
    && install -m 0755 /root/.local/bin/uv /usr/local/bin/uv \
    && rm -rf /root/.local

RUN useradd -m -s /bin/bash agent

WORKDIR /workspace

RUN git config --system --add safe.directory '*' \
    && git config --system init.defaultBranch main \
    && git config --system core.autocrlf false \
    && git config --system advice.detachedHead false

# Make `codex`, `claude`, and `opencode` inside an interactive container shell
# behave like their launcher defaults: the container is the outer sandbox, so
# default to full-access modes. Explicit override flags still win.
RUN cat >> /etc/bash.bashrc <<'EOF'

codex() {
    for arg in "$@"; do
        case "$arg" in
            --sandbox|--sandbox=*|-s|-s?*|--dangerously-bypass-approvals-and-sandbox|--yolo)
                command codex "$@"
                return
                ;;
        esac
    done
    command codex --sandbox danger-full-access "$@"
}

claude() {
    for arg in "$@"; do
        case "$arg" in
            --permission-mode|--permission-mode=*|--dangerously-skip-permissions|--allow-dangerously-skip-permissions)
                command claude "$@"
                return
                ;;
        esac
    done
    command claude --dangerously-skip-permissions "$@"
}

opencode() {
    for arg in "$@"; do
        case "$arg" in
            --auto|--yolo|--dangerously-skip-permissions)
                command opencode "$@"
                return
                ;;
        esac
    done
    command opencode --dangerously-skip-permissions "$@"
}
EOF

RUN mkdir -p \
      /run/sshd \
      /home/agent/.ssh \
      /home/agent/.codex \
      /home/agent/.claude \
      /home/agent/.cache \
      /home/agent/.config/opencode \
      /home/agent/.local/share/opencode \
      /workspace \
    && chmod 700 /home/agent/.ssh \
    && chown -R agent:agent /home/agent \
    && chown agent:agent /workspace \
    && ssh-keygen -A \
    && printf '\nPermitRootLogin no\nPasswordAuthentication yes\n' >> /etc/ssh/sshd_config \
    && /usr/sbin/sshd -t

COPY agent-entrypoint /usr/local/bin/agent-entrypoint
RUN chmod 0755 /usr/local/bin/agent-entrypoint

RUN set -eux; \
    test -x /usr/sbin/chpasswd; \
    python --version; \
    pip --version; \
    ruby --version; \
    gem --version; \
    bundle --version; \
    node --version; \
    npm --version; \
    git --version; \
    gh --version; \
    docker --version; \
    pwsh --version; \
    gcc --version; \
    g++ --version; \
    make --version; \
    cmake --version; \
    rg --version; \
    jq --version; \
    minify --version; \
    ansible --version; \
    shellcheck --version; \
    strace --version; \
    gdb --version; \
    ssh -V; \
    claude --version; \
    codex --version; \
    opencode --version; \
    uv --version

ENTRYPOINT ["/usr/local/bin/agent-entrypoint"]
CMD ["bash"]
