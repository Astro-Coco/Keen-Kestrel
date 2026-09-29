#!/usr/bin/env bash
# Installe les prérequis HÔTE (Ubuntu/Debian, WSL compris) : Docker Engine + plugin
# Compose, accès docker sans sudo, et nvidia-container-toolkit si un GPU NVIDIA est
# utilisable. Idempotent : chaque étape déjà faite est sautée. Demande sudo.
set -euo pipefail

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
todo() { printf '  \033[36m→\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Lancer en utilisateur normal (sudo est demandé au besoin), pas en root"
command -v apt-get >/dev/null || die "Distribution sans apt : installer Docker à la main (https://docs.docker.com/engine/install/)"

wsl=false; grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && wsl=true

# --- Plan ------------------------------------------------------------------------
need_docker=false; need_group=false; need_nvidia=false
command -v docker >/dev/null && docker compose version >/dev/null 2>&1 || need_docker=true
id -nG | grep -qw docker || need_group=true
# WSL : le GPU passe par /dev/dxg (compose.wsl.yaml), pas par le toolkit.
if ! $wsl && command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; then
  command -v nvidia-ctk >/dev/null && grep -qs nvidia /etc/docker/daemon.json || need_nvidia=true
elif ! $wsl && command -v lspci >/dev/null && lspci | grep -qi 'vga.*nvidia\|3d.*nvidia'; then
  warn "GPU NVIDIA présent mais driver absent : sudo ubuntu-drivers install, redémarrer, puis relancer make host-deps"
fi

echo "Prérequis hôte :"
$need_docker && todo "installer Docker Engine + Compose (script officiel get.docker.com)" || ok "Docker + Compose"
$need_group  && todo "ajouter $USER au groupe docker"                                     || ok "groupe docker"
$need_nvidia && todo "installer nvidia-container-toolkit (redémarre le démon Docker)"      || ok "GPU : rien à installer"

if ! $need_docker && ! $need_group && ! $need_nvidia; then
  echo; echo "Rien à faire. Prochaine étape : make sim"; exit 0
fi
if $wsl && $need_docker; then
  warn "WSL : installer Docker DANS la distro (ce script) et NE PAS utiliser Docker Desktop en parallèle"
fi

echo
read -rp "Continuer ? [Y/n] " ans
[[ "${ans:-Y}" =~ ^[Yy]$ ]] || exit 1

# --- Exécution --------------------------------------------------------------------
if $need_docker; then
  curl -fsSL https://get.docker.com | sudo sh
  ok "Docker installé"
fi

if $need_group; then
  sudo usermod -aG docker "$USER"
  ok "$USER ajouté au groupe docker"
fi

if $need_nvidia; then
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker   # coupe les conteneurs en cours sur l'hôte
  ok "nvidia-container-toolkit installé"
fi

echo
if $need_group; then
  echo "Terminé. Déconnecte-toi puis reconnecte-toi (ou redémarre) pour activer le groupe docker,"
  echo "puis lance : make sim"
else
  echo "Terminé. Prochaine étape : make sim"
fi
