#!/usr/bin/env bash
# =============================================================================
# socle-os.sh — Applique le socle OS de PROD-01 (phase 3) sur une Ubuntu Server
# fraîchement installée. Prévu pour reconstruire PROD-01 ou la PPROD (N100).
#
# Prérequis (à faire AVANT, voir docs/runbooks/socle-os.md) :
#   - IP réservée sur la Livebox
#   - clé SSH du poste d'administration déjà déposée dans ~/.ssh/authorized_keys
#     ET testée (sinon on se verrouille dehors)
#
# Usage : sudo ./socle-os.sh
# Le script est rejouable (idempotent) : le relancer ne casse rien.
# =============================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Lancer avec sudo."; exit 1; }

ADMIN_USER="${SUDO_USER:-gael}"

# --- Garde-fou : refuser de couper les mots de passe sans clé autorisée -----
if [[ ! -s "/home/${ADMIN_USER}/.ssh/authorized_keys" ]]; then
  echo "ERREUR : aucune clé dans /home/${ADMIN_USER}/.ssh/authorized_keys."
  echo "Déposer et tester une clé SSH avant de lancer ce script."
  exit 1
fi

echo "==> Fuseau horaire"
timedatectl set-timezone Europe/Paris

echo "==> Mises à jour"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get install -y rfkill smartmontools nvme-cli lm-sensors

echo "==> SSH : clés uniquement (ADR-017)"
cat > /etc/ssh/sshd_config.d/10-prod01.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sshd -t
systemctl restart ssh

echo "==> Swap supprimé"
if swapon --show | grep -q '/swap.img'; then swapoff /swap.img; fi
sed -i '\|^/swap.img|d' /etc/fstab
rm -f /swap.img

echo "==> Wi-Fi et Bluetooth coupés"
rfkill block wlan || true
rfkill block bluetooth || true

echo "==> Vérification"
timedatectl | grep -E 'Time zone|synchronized'
free -h | grep -i swap
rfkill list | grep -i soft || true
sshd -T | grep -Ei '^(passwordauthentication|permitrootlogin)'
[[ -f /var/run/reboot-required ]] && echo "REDÉMARRAGE REQUIS" || echo "Pas de redémarrage requis"

echo
echo "Terminé. AVANT de fermer cette session : tester 'ssh <hôte> hostname' depuis une nouvelle fenêtre."
