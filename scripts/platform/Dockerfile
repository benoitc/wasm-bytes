# A Linux host for the platform check: Erlang/OTP from the official image and
# the Wasmtime release named by WASMTIME_VERSION, for the image's CPU.
ARG OTP_IMAGE=erlang:29
FROM ${OTP_IMAGE}
ARG WASMTIME_VERSION=50.0.1
RUN set -eu; \
    case "$(uname -m)" in \
        aarch64|arm64) arch=aarch64 ;; \
        x86_64|amd64) arch=x86_64 ;; \
        *) echo "no Wasmtime release for $(uname -m)" >&2; exit 1 ;; \
    esac; \
    name="wasmtime-v${WASMTIME_VERSION}-${arch}-linux"; \
    curl -fsSL "https://github.com/bytecodealliance/wasmtime/releases/download/v${WASMTIME_VERSION}/${name}.tar.xz" \
        | tar -xJ -C /opt; \
    ln -s "/opt/${name}/wasmtime" /usr/local/bin/wasmtime; \
    wasmtime --version
