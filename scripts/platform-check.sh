#!/bin/sh
# Replays a recorded module on Linux, in a container, with erlang_wasm and
# Wasmtime, and writes the run record to evidence/runs/.
#
#   scripts/platform-check.sh                 linux/arm64
#   scripts/platform-check.sh linux/amd64     x86_64, emulated on an arm64 host
#
# REPLY names another reply file and TASK its task (write by default). OTP_IMAGE and WASMTIME_VERSION pick the
# Erlang image and the Wasmtime release. The repository is mounted read-only
# and copied inside the container, so the host's _build is not used.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PLATFORM=${1:-linux/arm64}
REPLY=${REPLY:-trials/write/claude-sonnet-5-5-1/reply.txt}
TASK=${TASK:-write}
OTP_IMAGE=${OTP_IMAGE:-erlang:29}
WASMTIME_VERSION=${WASMTIME_VERSION:-50.0.1}
TAG="wasm-bytes-platform:$(printf '%s' "$PLATFORM" | tr '/' '-')"

HOST_ARCH=$(uname -m)
# Under CPU emulation the BEAM JIT cannot boot with its default dual-mapped
# code memory; +JMsingle keeps the JIT on with one mapping. It changes how the
# Erlang VM maps its own code, not how either engine runs the module.
ERL_FLAGS=""
case "$PLATFORM:$HOST_ARCH" in
    linux/arm64:arm64|linux/arm64:aarch64|linux/amd64:x86_64)
        NOTE="Linux container, native CPU, on a $(uname -s) $HOST_ARCH host" ;;
    *)
        ERL_FLAGS="+JMsingle true"
        NOTE="Linux container, CPU emulated by Docker, on a $(uname -s) $HOST_ARCH host; Erlang run with +JMsingle true" ;;
esac

docker build --quiet --platform "$PLATFORM" \
    --build-arg OTP_IMAGE="$OTP_IMAGE" --build-arg WASMTIME_VERSION="$WASMTIME_VERSION" \
    -t "$TAG" "$ROOT/scripts/platform" >/dev/null

mkdir -p "$ROOT/evidence/runs"
docker run --rm --platform "$PLATFORM" \
    -e WASM_BYTES_HOST_NOTE="$NOTE" -e REPLY="$REPLY" -e TASK="$TASK" -e ERL_FLAGS="$ERL_FLAGS" \
    -v "$ROOT":/src:ro -v "$ROOT/evidence/runs":/out \
    "$TAG" sh -c '
        set -eu
        mkdir /work
        cd /src && tar --exclude=./_build --exclude=./.git -cf - . | tar -xf - -C /work
        cd /work
        bin/wasm-bytes compare "$TASK" "$REPLY" --record /out'
