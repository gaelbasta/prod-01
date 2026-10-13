#!/usr/bin/env bash
# =============================================================================
# coffre-sauvegardes.sh — Transforme pprod-01 en coffre de sauvegarde
# (ADR-027, ADR-028) : pare-feu, rest-server en append-only, disque 3,5".
#
# Prérequis : socle-os.sh appliqué (voir docs/runbooks/installation-pprod-01.md).
#
# Usage : une sous-commande à la fois, dans cet ordre, en vérifiant entre deux :
#   sudo bash coffre-sauvegardes.sh pare-feu     # ufw : SSH (LAN) + rest-server (PROD-01 seul)
#   sudo bash coffre-sauvegardes.sh rest-server  # paquets, utilisateur, identifiant, service
#   (disque : ajouté après le test SMART long — formatage + montage /srv/sauvegardes)
#
# Rejouable (idempotent) : relancer une sous-commande ne casse rien.
# =============================================================================
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Lancer avec sudo."; exit 1; }

LAN="192.168.1.0/24"
PROD01_IP="192.168.1.16"          # seul déposant autorisé (ADR-027)
PORT=8000                         # port par défaut de rest-server
POINT_MONTAGE="/srv/sauvegardes"  # disque 3,5" (monté par la sous-commande disque)
DEPOT="${POINT_MONTAGE}/restic"   # dossier servi par rest-server
HTPASSWD="/etc/rest-server/.htpasswd"
UTILISATEUR_REST="prod-01"        # identifiant rest-server de PROD-01 (= son sous-dossier)

pare_feu() {
  echo "==> Pare-feu ufw (ADR-027)"
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow from "$LAN" to any port 22 proto tcp comment 'SSH depuis le LAN'
  ufw allow from "$PROD01_IP" to any port "$PORT" proto tcp comment 'rest-server depuis PROD-01 uniquement'
  ufw --force enable
  ufw status verbose
}

rest_server() {
  echo "==> Paquets Ubuntu (ADR-028)"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y restic restic-rest-server apache2-utils
  BIN="$(command -v rest-server)"
  echo "rest-server : $BIN"
  restic version
  "$BIN" --version || true

  echo "==> Service éventuellement fourni par le paquet : désactivé (on utilise le nôtre)"
  for u in $(systemctl list-unit-files --no-legend 'restic-rest-server*' | awk '{print $1}'); do
    systemctl disable --now "$u" || true
  done

  echo "==> Utilisateur système 'restic' (sans connexion possible)"
  id restic >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin restic

  echo "==> Identifiant rest-server de PROD-01 (mot de passe : gestionnaire de mots de passe)"
  install -d -m 750 -o root -g restic /etc/rest-server
  if [[ -s "$HTPASSWD" ]] && grep -q "^${UTILISATEUR_REST}:" "$HTPASSWD"; then
    echo "Identifiant '${UTILISATEUR_REST}' déjà présent : inchangé."
  else
    echo "Saisir (deux fois) le mot de passe rangé dans le gestionnaire :"
    htpasswd -B -c "$HTPASSWD" "$UTILISATEUR_REST"
  fi
  chown root:restic "$HTPASSWD"
  chmod 640 "$HTPASSWD"

  echo "==> Service systemd rest-server"
  cat > /etc/systemd/system/rest-server.service <<EOF
# Géré par prod-01/scripts/coffre-sauvegardes.sh — ADR-027, ADR-028
[Unit]
Description=rest-server : dépôt restic en append-only (ADR-027)
After=network-online.target
Wants=network-online.target
# Garde-fou : ne démarre JAMAIS si le disque n'est pas monté
# (sinon les sauvegardes rempliraient le SSD système, dans un dossier vide).
RequiresMountsFor=${POINT_MONTAGE}
ConditionPathIsMountPoint=${POINT_MONTAGE}

[Service]
User=restic
Group=restic
ExecStart=${BIN} --path ${DEPOT} --listen :${PORT} --append-only --private-repos --htpasswd-file ${HTPASSWD}
Restart=on-failure
RestartSec=10
# Durcissement : le service ne peut écrire que dans le dépôt
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=${DEPOT}

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable rest-server.service
  echo "Service activé au démarrage, mais NON démarré : il attend le disque (sous-commande disque)."
  systemctl status rest-server.service --no-pager || true
}

case "${1:-}" in
  pare-feu)    pare_feu ;;
  rest-server) rest_server ;;
  *) echo "Usage : sudo bash $0 {pare-feu|rest-server}"; exit 1 ;;
esac
