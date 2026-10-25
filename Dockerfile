# Coolify Abbild mit neu gebautem MinIO Client (mc) und cloudflared.
#
# Das offizielle Abbild coollabsio/coolify bringt beide Go Programme als fertige
# Binaries mit (mc aus quay.io/minio/aistor/mc, cloudflared aus dem GitHub Release).
# Trivy meldet darin HIGH Befunde in der Go Standardbibliothek, golang.org/x/net,
# google.golang.org/grpc (mc) und github.com/klauspost/compress (cloudflared).
# Hier werden beide aus der Quelle mit aktuellem Go und angehobenen Modulen gebaut
# und an dieselben Pfade mit denselben Rechten kopiert. Alles andere bleibt das
# offizielle Abbild, auch Entrypoint, Cmd und Nutzer.
#
# BASE setzt die Pipeline auf den Digest von coollabsio/coolify:<version>,
# CLOUDFLARED_REF auf die cloudflared Version, die im Basisabbild steckt.
ARG BASE=coollabsio/coolify:4.5.0
ARG GO_IMAGE=golang:1.27.3-alpine
ARG MC_REF=RELEASE.2025-08-13T08-35-41Z
ARG CLOUDFLARED_REF=2026.10.3

FROM ${GO_IMAGE} AS gobase
RUN apk add --no-cache git make
ENV CGO_ENABLED=0 GOTOOLCHAIN=local GOFLAGS=-trimpath
COPY scripts/raise-modules.sh /usr/local/bin/raise-modules

# MinIO Client: letztes Release aus github.com/minio/mc (Repo archiviert).
FROM gobase AS mc
ARG MC_REF
ARG MC_MODULES="golang.org/x/net@v0.60.0 google.golang.org/grpc@v1.83.2 github.com/klauspost/compress@v1.18.7 github.com/prometheus/prometheus@v0.311.3"
WORKDIR /src/mc
RUN git clone -q --depth 1 --branch "${MC_REF}" https://github.com/minio/mc.git . \
 && sh /usr/local/bin/raise-modules ${MC_MODULES}
RUN set -eu; \
    t=$(echo "${MC_REF#RELEASE.}" | sed -E 's/T([0-9]{2})-([0-9]{2})-([0-9]{2})Z$/T\1:\2:\3Z/'); \
    ldflags=$(MC_RELEASE=RELEASE go run buildscripts/gen-ldflags.go "$t"); \
    go build -tags kqueue -ldflags "$ldflags" -o /out/mc . \
 && /out/mc --version

# cloudflared: Release Tag, Bau wie upstream per make (ohne FIPS, ohne Container Flag,
# wie das Release Binary im offiziellen Coolify Abbild).
FROM gobase AS cloudflared
ARG CLOUDFLARED_REF
ARG CLOUDFLARED_MODULES="github.com/klauspost/compress@v1.18.7"
WORKDIR /src/cloudflared
RUN git clone -q --depth 1 --branch "${CLOUDFLARED_REF}" https://github.com/cloudflare/cloudflared.git . \
 && sh /usr/local/bin/raise-modules ${CLOUDFLARED_MODULES}
RUN set -eu; \
    date=$(git log -1 --format=%cd --date=format-local:'%Y-%m-%d-%H:%M UTC'); \
    TZ=UTC make cloudflared DATE="$date" \
 && mkdir -p /out && mv cloudflared /out/cloudflared \
 && /out/cloudflared --version

FROM ${BASE}
COPY --from=mc --chown=0:0 --chmod=755 /out/mc /usr/bin/mc
COPY --from=cloudflared --chown=0:0 --chmod=755 /out/cloudflared /usr/local/bin/cloudflared
