# syntax=docker/dockerfile:1

ARG GO_VERSION=1.27.0
ARG NODE_VERSION=26.7.0
ARG DEBIAN_RELEASE=trixie
ARG ANUBIS_VERSION=1.27.0
ARG ANUBIS_SOURCE_SHA256=1383dcc8a713306be9e93be5f1cd18a4838f1820383f145d59716fcee5618183

FROM golang:${GO_VERSION}-${DEBIAN_RELEASE} AS go-toolchain

FROM node:${NODE_VERSION}-${DEBIAN_RELEASE} AS build

COPY --from=go-toolchain /usr/local/go/ /usr/local/go/

ENV PATH="/usr/local/go/bin:${PATH}"

ARG ANUBIS_VERSION
ARG ANUBIS_SOURCE_SHA256

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        brotli \
        ca-certificates \
        gzip \
        patch \
        zstd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/anubis

RUN curl --fail --location --show-error \
        --output /tmp/anubis.tar.gz \
        "https://github.com/TecharoHQ/anubis/releases/download/v${ANUBIS_VERSION}/anubis-src-vendor-${ANUBIS_VERSION}.tar.gz" \
    && echo "${ANUBIS_SOURCE_SHA256}  /tmp/anubis.tar.gz" | sha256sum --check --strict \
    && tar --extract --gzip --file /tmp/anubis.tar.gz \
        --strip-components=1 --directory /usr/src/anubis \
    && rm /tmp/anubis.tar.gz

COPY patches/ /tmp/patches/

# Patch names determine application order, so prefix them with a sequence number.
RUN set -eux; \
    for patch_file in /tmp/patches/*.patch; do \
        [ -e "${patch_file}" ] || break; \
        patch --batch --forward --strip=1 < "${patch_file}"; \
    done

RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    --mount=type=cache,target=/go/pkg/mod,sharing=locked \
    HUSKY=0 npm ci

RUN --mount=type=cache,target=/root/.cache/go-build,sharing=locked \
    --mount=type=cache,target=/go/pkg/mod,sharing=locked \
    npm run assets \
    && CGO_ENABLED=0 go build \
        -buildvcs=false \
        -trimpath \
        -ldflags="-s -w -X github.com/TecharoHQ/anubis.Version=${ANUBIS_VERSION}" \
        -o /usr/local/bin/anubis \
        ./cmd/anubis

FROM scratch AS runtime

ARG ANUBIS_VERSION

LABEL org.opencontainers.image.source="https://github.com/TecharoHQ/anubis" \
      org.opencontainers.image.version="${ANUBIS_VERSION}"

COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /usr/local/bin/anubis /anubis

USER 1000:1000
EXPOSE 8923

ENTRYPOINT ["/anubis"]
