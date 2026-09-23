# ============================================================================
# Stage 0: Security-pinned bubblewrap
# ============================================================================
FROM node:22-slim AS bubblewrap-builder

ARG BUBBLEWRAP_VERSION=0.12.0
ARG BUBBLEWRAP_SHA256=9760d007363e3abba7c747489910f9f82d9fca53ba3bd3282e396fa3c97a3314

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  libcap-dev \
  meson \
  ninja-build \
  pkg-config \
  xz-utils \
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsSL \
    "https://github.com/containers/bubblewrap/releases/download/v${BUBBLEWRAP_VERSION}/bubblewrap-${BUBBLEWRAP_VERSION}.tar.xz" \
    -o /tmp/bubblewrap.tar.xz \
  && echo "${BUBBLEWRAP_SHA256}  /tmp/bubblewrap.tar.xz" | sha256sum -c - \
  && mkdir /tmp/bubblewrap \
  && tar -xJf /tmp/bubblewrap.tar.xz -C /tmp/bubblewrap --strip-components=1 \
  && meson setup /tmp/bubblewrap/_build /tmp/bubblewrap \
    --buildtype=release \
    --prefix=/usr/local \
    -Dbash_completion=disabled \
    -Dman=disabled \
    -Dselinux=disabled \
    -Dtests=false \
    -Dzsh_completion=disabled \
  && meson compile -C /tmp/bubblewrap/_build \
  && DESTDIR=/tmp/bubblewrap-install meson install -C /tmp/bubblewrap/_build

# ============================================================================
# Stage 1: Shared Base
# ============================================================================
FROM node:22-slim AS base

RUN apt-get update && apt-get install -y \
  sqlite3 \
  git \
  curl \
  sudo \
  vim \
  procps \
  htop \
  lsof \
  net-tools \
  iputils-ping \
  wget \
  jq \
  less \
  tree \
  openssh-client \
  ripgrep \
  libcap2 \
  util-linux \
  && rm -rf /var/lib/apt/lists/*

COPY --from=bubblewrap-builder /tmp/bubblewrap-install/usr/local/bin/bwrap /usr/local/bin/bwrap

RUN ZELLIJ_VERSION=0.43.1 && \
  curl -L "https://github.com/zellij-org/zellij/releases/download/v${ZELLIJ_VERSION}/zellij-x86_64-unknown-linux-musl.tar.gz" | \
  tar -xz -C /usr/local/bin && \
  chmod +x /usr/local/bin/zellij

RUN curl -fsSL "$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep 'browser_download_url.*linux_amd64.tar.gz"' | cut -d'"' -f4)" | \
  tar -xz -C /tmp && \
  mv /tmp/gh_*/bin/gh /usr/local/bin/ && \
  rm -rf /tmp/gh_*

RUN npm install -g pnpm@11.17.0

ARG UID=1000
ARG GID=1000

RUN set -eux; \
    usermod -l agor -d /home/agor -m -u "${UID}" node; \
    if getent group "${GID}" >/dev/null; then \
      groupmod -n agor "$(getent group "${GID}" | cut -d: -f1)"; \
    else \
      groupmod -n agor -g "${GID}" node; \
    fi; \
    usermod -g agor agor; \
    echo "agor ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agor; \
    chmod 0440 /etc/sudoers.d/agor; \
    mkdir -p -m 0700 /home/agor/.agor; \
    chown -R agor:agor /home/agor

COPY docker/zellij-config.kdl /tmp/zellij-config.kdl
RUN mkdir -p /home/agor/.config/zellij && \
    cp /tmp/zellij-config.kdl /home/agor/.config/zellij/config.kdl && \
    chown -R agor:agor /home/agor/.config && \
    rm /tmp/zellij-config.kdl

WORKDIR /app
USER agor

# ============================================================================
# Stage 2: Production (Default target)
# ============================================================================
FROM base AS production

USER root
RUN npm install -g agor-live@latest
USER agor

COPY docker/docker-entrypoint-prod.sh /usr/local/bin/
RUN sudo chmod +x /usr/local/bin/docker-entrypoint-prod.sh && \
    sudo chown agor:agor /usr/local/bin/docker-entrypoint-prod.sh

EXPOSE 3030

ENTRYPOINT ["docker-entrypoint-prod.sh"]
