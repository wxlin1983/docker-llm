#!/usr/bin/env bash
# Host-side helper: installs gVisor (runsc) and registers it as a Docker runtime.
# Run this on the Docker HOST, not inside the sandbox container.
# After it succeeds, uncomment `runtime: runsc` in docker-compose.yml.
#
# Reference: https://gvisor.dev/docs/user_guide/install/
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required on the host before installing gVisor." >&2
    exit 1
fi

ARCH=$(uname -m)
case "${ARCH}" in
    x86_64) ARCH=x86_64 ;;
    aarch64) ARCH=aarch64 ;;
    *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

URL="https://storage.googleapis.com/gvisor/releases/release/latest/${ARCH}"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

curl -fsSL "${URL}/runsc" -o "${TMP_DIR}/runsc"
curl -fsSL "${URL}/runsc.sha512" -o "${TMP_DIR}/runsc.sha512"
curl -fsSL "${URL}/containerd-shim-runsc-v1" -o "${TMP_DIR}/containerd-shim-runsc-v1"
curl -fsSL "${URL}/containerd-shim-runsc-v1.sha512" -o "${TMP_DIR}/containerd-shim-runsc-v1.sha512"

(cd "${TMP_DIR}" && sha512sum -c runsc.sha512 && sha512sum -c containerd-shim-runsc-v1.sha512)

chmod a+rx "${TMP_DIR}/runsc" "${TMP_DIR}/containerd-shim-runsc-v1"
sudo mv "${TMP_DIR}/runsc" "${TMP_DIR}/containerd-shim-runsc-v1" /usr/local/bin/

sudo /usr/local/bin/runsc install
sudo systemctl restart docker

echo "gVisor (runsc) installed and registered with Docker."
echo "Verify with: docker run --rm --runtime=runsc hello-world"
echo "Then uncomment 'runtime: runsc' in docker-compose.yml."
