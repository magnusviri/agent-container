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
    MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CONFIG_DIR=/etc/mise \
    PATH=/usr/local/share/mise/shims:/usr/local/bin:/usr/bin:/bin

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
    ripgrep \
    jq \
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
    docker.io \
    && rm -rf /var/lib/apt/lists/*

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

WORKDIR /workspace

RUN git config --system --add safe.directory '*' \
    && git config --system init.defaultBranch main \
    && git config --system core.autocrlf false \
    && git config --system advice.detachedHead false

RUN mkdir -p \
      /run/sshd \
      /root/.ssh \
      /root/.codex \
      /root/.claude \
      /root/.opencode \
      /root/.cache \
      /root/.config \
      /workspace \
    && chmod 700 /root/.ssh \
    && ssh-keygen -A \
    && printf '\nPermitRootLogin yes\nPasswordAuthentication yes\n' >> /etc/ssh/sshd_config \
    && /usr/sbin/sshd -t

EXPOSE 22 1455

COPY agent-entrypoint /usr/local/bin/agent-entrypoint
RUN chmod 0755 /usr/local/bin/agent-entrypoint

RUN set -eux; \
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
    gcc --version; \
    g++ --version; \
    make --version; \
    cmake --version; \
    rg --version; \
    jq --version; \
    shellcheck --version; \
    strace --version; \
    gdb --version; \
    ssh -V; \
    claude --version; \
    codex --version; \
    opencode --version

ENTRYPOINT ["/usr/local/bin/agent-entrypoint"]
CMD ["bash"]
