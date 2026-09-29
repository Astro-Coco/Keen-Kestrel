#!/usr/bin/env bash
# Vérifie les prérequis de l'hôte, détecte la plateforme GPU et écrit COMPOSE_FILE
# dans .env (créé depuis .env.example au besoin). Idempotent : les autres lignes de
# .env ne sont jamais touchées. Forcer une plateforme : PLATFORM=intel make configure
set -euo pipefail
cd "$(dirname "$0")/.."

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

echo "Vérification de l'hôte :"
command -v docker >/dev/null \
  || die "Docker absent → make host-deps"
docker compose version >/dev/null 2>&1 \
  || die "Compose v2 absent → make host-deps"
docker info >/dev/null 2>&1 \
  || die "Docker inaccessible sans sudo → make host-deps, puis se déconnecter/reconnecter"
ok "Docker + Compose v2"

detect() {
  if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then echo wsl; return; fi
  if command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; then
    if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q nvidia; then echo nvidia; return; fi
    warn "GPU NVIDIA détecté mais nvidia-container-toolkit absent : rendu dégradé → make host-deps, puis make configure"
  fi
  if compgen -G '/dev/dri/renderD*' >/dev/null; then echo intel; return; fi
  echo cpu
}

PLATFORM=${PLATFORM:-$(detect)}
case "$PLATFORM" in
  nvidia|intel|wsl) CF="compose.yaml:compose.$PLATFORM.yaml" ;;
  cpu)              CF="compose.yaml"; warn "Aucun GPU utilisable : rendu logiciel (Gazebo lent mais fonctionnel)" ;;
  *)                die "PLATFORM inconnue : $PLATFORM (nvidia | intel | wsl | cpu)" ;;
esac

if [ "$PLATFORM" = wsl ]; then
  docker info --format '{{.OperatingSystem}}' | grep -qi 'docker desktop' \
    && die "Docker Desktop détecté : installer Docker Engine DANS la distro WSL (README §2.4)"
  [ -d /mnt/wslg ] || die "/mnt/wslg absent : WSLg requis (Windows 11)"
fi
ok "Plateforme : $PLATFORM"

[ -n "${DISPLAY:-}" ] || warn "Pas de DISPLAY : les fenêtres Gazebo/RViz ne s'ouvriront pas (make sitl fonctionne sans)"

[ -f .env ] || cp .env.example .env
if grep -q '^COMPOSE_FILE=' .env; then
  sed -i "s|^COMPOSE_FILE=.*|COMPOSE_FILE=$CF|" .env
else
  printf 'COMPOSE_FILE=%s\n' "$CF" >> .env
fi
ok ".env → COMPOSE_FILE=$CF"
