#!/usr/bin/env bash
set -euo pipefail

############################################
# Install + deploy Grafana only            #
# - Installs Docker/Compose if missing     #
# - Configures UFW firewall                #
# - Allows 3000 ONLY from NPM_IP           #
############################################

# ---- go to repo root (script dir) ----
cd "$(dirname "$0")"

# ---- Config ----
NPM_IP="${NPM_IP:-34.118.175.190}"

need_cmd() { command -v "$1" >/dev/null 2>&1; }

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: ejecutá como root (o con sudo)." >&2
  exit 1
fi

echo "[install] start: $(date -Iseconds)"

# ---- Ensure base packages ----
if need_cmd apt-get; then
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release
else
  echo "ERROR: este script asume Debian/Ubuntu (apt-get)." >&2
  exit 1
fi

# ---- Install Docker + Compose v2 if missing ----
if ! need_cmd docker; then
  echo "[install] Docker no encontrado. Instalando Docker Engine + Compose v2..."

  install -m 0755 -d /etc/apt/keyrings

  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  fi
  chmod a+r /etc/apt/keyrings/docker.gpg

  CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
  ARCH="$(dpkg --print-architecture)"

  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable
EOF

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable docker
  systemctl restart docker
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: Docker Compose v2 plugin no está disponible (docker compose)." >&2
  exit 1
fi

# ---- Firewall (UFW) ----
if ! need_cmd ufw; then
  echo "[install] ufw no está instalado. Instalando..."
  apt-get install -y ufw
fi

echo "[install] configurando UFW..."

# Seguridad base
ufw allow 22/tcp >/dev/null || true

# Grafana: SOLO desde NPM
ufw delete allow 3000/tcp >/dev/null 2>&1 || true
ufw allow from "${NPM_IP}" to any port 3000 proto tcp >/dev/null || true

ufw --force enable >/dev/null || true
ufw status verbose || true

# ---- Deploy (Grafana only) ----
echo "[install] levantando Grafana..."
docker compose -f docker-compose.yml up -d

echo "[install] estado:"
docker compose -f docker-compose.yml ps

echo "[install] done."
echo "Notas:"
echo "- 3000 sólo acepta desde NPM_IP=${NPM_IP}"
