# Copyright 2021 The HAProxy Ingress Controller Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM golang:1.17.11-alpine AS builder

ARG GIT_TAG
WORKDIR /src
RUN apk --no-cache add git

COPY . .

RUN GIT_TAG=${GIT_TAG:-latest}\
 && GIT_COMMIT=git-$(git rev-parse --short HEAD)\
 && GIT_REPO=$(git config --get remote.origin.url)\
 && VERSION_PKG=github.com/jcmoraisjr/haproxy-ingress/pkg/version\
 && CGO_ENABLED=0 go build\
    -ldflags "-s -w -X ${VERSION_PKG}.RELEASE=${GIT_TAG} -X ${VERSION_PKG}.COMMIT=${GIT_COMMIT} -X ${VERSION_PKG}.REPO=${GIT_REPO}"\
    -o haproxy-ingress pkg/main.go


FROM ubuntu:lunar as base

# We use a custom haproxy image based on the official Dockerfile (from https://github.com/docker-library/haproxy/blob/b8c3d54e118f694d0a06ce94d8f83a0a2cad5c56/2.7/Dockerfile)
# so we have an haproxy version that supports OpenSSL3.
# Currently using Ubuntu 22.04 since it will be released in the next few days.
FROM base as haproxy-ossl3

RUN apt-get update && apt-get install -y --no-install-recommends  \
        openssl \
        liblua5.3

# roughly, https://salsa.debian.org/haproxy-team/haproxy/-/blob/732b97ae286906dea19ab5744cf9cf97c364ac1d/debian/haproxy.postinst#L5-6
RUN set -eux; \
    groupadd --gid 99 --system haproxy; \
    useradd \
        --gid haproxy \
        --home-dir /var/lib/haproxy \
        --no-create-home \
        --system \
        --uid 99 \
        haproxy \
    ; \
    mkdir /var/lib/haproxy; \
    chown haproxy:haproxy /var/lib/haproxy

ENV HAPROXY_VERSION 2.7.6
ENV HAPROXY_URL https://www.haproxy.org/download/2.7/src/haproxy-2.7.6.tar.gz
ENV HAPROXY_SHA256 133f357ddb3fcfc5ad8149ef3d74cbb5db6bb4a5ab67289ce0b0ab686cdeb74f

# see https://sources.debian.net/src/haproxy/jessie/debian/rules/ for some helpful navigation of the possible "make" arguments
RUN set -eux; \
    \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        gcc \
        libc6-dev \
        liblua5.3-dev \
        libpcre2-dev \
        libssl-dev \
        make \
        wget \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    \
    wget -O haproxy.tar.gz "$HAPROXY_URL"; \
    echo "$HAPROXY_SHA256 *haproxy.tar.gz" | sha256sum -c; \
    mkdir -p /usr/src/haproxy; \
    tar -xzf haproxy.tar.gz -C /usr/src/haproxy --strip-components=1; \
    rm haproxy.tar.gz; \
    \
    makeOpts=' \
        TARGET=linux-glibc \
        USE_GETADDRINFO=1 \
        USE_LUA=1 LUA_INC=/usr/include/lua5.3 \
        USE_OPENSSL=1 \
        USE_PCRE2=1 USE_PCRE2_JIT=1 \
        USE_PROMEX=1 \
        \
        EXTRA_OBJS=" \
        " \
    '; \
# https://salsa.debian.org/haproxy-team/haproxy/-/commit/53988af3d006ebcbf2c941e34121859fd6379c70
    dpkgArch="$(dpkg --print-architecture)"; \
    case "$dpkgArch" in \
        armel) makeOpts="$makeOpts ADDLIB=-latomic" ;; \
    esac; \
    \
    nproc="$(nproc)"; \
    eval "make -C /usr/src/haproxy -j '$nproc' all $makeOpts"; \
    eval "make -C /usr/src/haproxy install-bin $makeOpts"; \
    \
    mkdir -p /usr/local/etc/haproxy; \
    cp -R /usr/src/haproxy/examples/errorfiles /usr/local/etc/haproxy/errors; \
    rm -rf /usr/src/haproxy; \
    \
    apt-mark auto '.*' > /dev/null; \
    [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
    find /usr/local -type f -executable -exec ldd '{}' ';' \
        | awk '/=>/ { print $(NF-1) }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -r apt-mark manual \
    ; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    \
# smoke test
    haproxy -v

# https://www.haproxy.org/download/1.8/doc/management.txt
# "4. Stopping and restarting HAProxy"
# "when the SIGTERM signal is sent to the haproxy process, it immediately quits and all established connections are closed"
# "graceful stop is triggered when the SIGUSR1 signal is sent to the haproxy process"
STOPSIGNAL SIGUSR1

#COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

USER haproxy

# https://github.com/docker-library/haproxy/issues/200
WORKDIR /var/lib/haproxy

#CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]

USER haproxy

# https://github.com/docker-library/haproxy/issues/200
WORKDIR /var/lib/haproxy

CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]

# Build PKCS#11 provider using same base as haproxy (same OpenSSL version)
FROM base as builder-pkcs11-provider

ARG PKCS11_PROVIDER_REPO_URL="https://github.com/quality-leftovers/pkcs11-provider.git"
ARG PKCS11_PROVIDER_BRANCH="pem"
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gnutls-bin gnupg2 p11-kit ca-certificates \
        build-essential git openssl libssl-dev automake pkg-config autoconf-archive libtool

RUN git clone "$PKCS11_PROVIDER_REPO_URL" "/tmp/pkcs11-provider" && cd "/tmp/pkcs11-provider" && \
    git checkout "$PKCS11_PROVIDER_BRANCH" && \
    autoreconf -fi && \
    ./configure && make install

FROM haproxy-ossl3 as haproxy-pkcs11
USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        socat lua5.3 lua-json dumb-init \
        p11-kit gnutls-bin gnupg2 `# PKCS#11 remoting` && \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false;

COPY rootfs/ /
COPY --from=builder /src/haproxy-ingress /haproxy-ingress-controller
COPY --from=builder-pkcs11-provider /usr/local/lib/ossl-modules /usr/local/lib/ossl-modules

RUN deluser haproxy\
 && addgroup -gid 1001 haproxy \
 && adduser --uid 1001 --ingroup haproxy --disabled-login --shell /bin/false --no-create-home haproxy\
 && mkdir -p /var/empty /etc/haproxy /var/lib/haproxy /var/run/haproxy\
 && chown -R haproxy:haproxy /etc/haproxy /var/lib/haproxy /var/run/haproxy\
 && chmod 0 /var/empty

STOPSIGNAL SIGTERM
ENV OPENSSL_CONF="/etc/ssl/openssl.pkcs11.cnf"
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/start.sh"]
