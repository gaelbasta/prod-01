#!/usr/bin/env bash
# =============================================================================
# install-k3s.sh — Installe K3s (version figée) + pare-feu ufw, comme sur PROD-01.
# Prérequis : socle-os.sh appliqué. Usage : sudo ./install-k3s.sh <fichier-config.yaml>
# Exemple   : sudo ./install-k3s.sh ../k3s/config.yaml
# =============================================================================
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Lancer avec sudo."; exit 1; }
CONFIG="${1:?Chemin du config.yaml K3s attendu}"
K3S_VERSION="v1.36.5+k3s1"     # même version que PROD-01 (ADR-014 : PPROD identique)
LAN="192.168.1.0/24"

echo "==> Configuration K3s"
install -D -m 600 "$CONFIG" /etc/rancher/k3s/config.yaml

echo "==> Installation K3s ${K3S_VERSION}"
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -

echo "==> Pare-feu ufw (ADR-020)"
ufw default deny incoming
ufw default allow outgoing
ufw allow from "$LAN" to any port 22 proto tcp comment 'SSH depuis le LAN'
ufw allow from "$LAN" to any port 6443 proto tcp comment 'API Kubernetes depuis le LAN'
ufw allow 80/tcp comment 'HTTP Traefik'
ufw allow 443/tcp comment 'HTTPS Traefik'
ufw allow from 10.42.0.0/16 comment 'K3s pods'
ufw allow from 10.43.0.0/16 comment 'K3s services'
ufw --force enable

echo "==> kubeconfig pour ${SUDO_USER:-gael}"
U="${SUDO_USER:-gael}"; H="/home/$U"
install -d -o "$U" -g "$U" "$H/.kube"
install -m 600 -o "$U" -g "$U" /etc/rancher/k3s/k3s.yaml "$H/.kube/config"
grep -q 'KUBECONFIG=~/.kube/config' "$H/.bashrc" || echo 'export KUBECONFIG=~/.kube/config' >> "$H/.bashrc"

echo "==> Vérification"
sleep 20
k3s kubectl get nodes -o wide
ufw status
echo "Renommer ensuite le contexte : kubectl config rename-context default <nom-du-serveur>"
