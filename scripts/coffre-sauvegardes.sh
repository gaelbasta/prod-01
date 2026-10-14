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
#   sudo bash coffre-sauvegardes.sh disque       # formate (une seule fois) + monte le disque, démarre rest-server
#   sudo bash coffre-sauvegardes.sh entretien-installer  # mot de passe restic, copie du script, timer du dimanche 5 h
#   sudo coffre-sauvegardes entretien            # tri (forget --prune) + contrôle complet (check --read-data)
#   sudo coffre-sauvegardes restic <commande>    # restic sur le dépôt prod-01, en utilisateur restic (ex. : snapshots)
#
# Rejouable (idempotent) : relancer une sous-commande ne casse rien.
# =============================================================================
set -euo pipefail
trap 'echo "ERREUR : arrêt à la ligne $LINENO (commande : $BASH_COMMAND)" >&2' ERR

[[ $EUID -eq 0 ]] || { echo "Lancer avec sudo."; exit 1; }

LAN="192.168.1.0/24"
PROD01_IP="192.168.1.16"          # seul déposant autorisé (ADR-027)
PORT=8000                         # port par défaut de rest-server
POINT_MONTAGE="/srv/sauvegardes"  # disque 3,5" (monté par la sous-commande disque)
DEPOT="${POINT_MONTAGE}/restic"   # dossier servi par rest-server
HTPASSWD="/etc/rest-server/.htpasswd"
UTILISATEUR_REST="prod-01"        # identifiant rest-server de PROD-01 (= son sous-dossier)
SERIE_DISQUE="WW6AR4CY"           # n° de série du disque de sauvegarde (Seagate IronWolf 4 To, lu par SMART)
ETIQUETTE="sauvegardes"           # étiquette du système de fichiers
DEPOT_PROD01="${DEPOT}/${UTILISATEUR_REST}"          # dossier du dépôt restic de PROD-01
MDP_PROD01="/etc/restic/prod-01.motdepasse"          # mot de passe restic (root:restic 640)
CIBLE="/usr/local/sbin/coffre-sauvegardes"           # copie installée (celle que lance le timer)
ETAT="/var/lib/entretien-sauvegardes"                # traces pour Home Assistant (phase 11)
# Rétention (ADR-030) : 14 jours, 8 semaines, 12 mois, 3 ans
RETENTION=(--keep-daily 14 --keep-weekly 8 --keep-monthly 12 --keep-yearly 3)

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
  # Le paquet Ubuntu installe la commande sous le nom « restic-rest-server »
  BIN="$(command -v restic-rest-server || command -v rest-server || true)"
  [[ -n "$BIN" ]] || { echo "ERREUR : commande rest-server introuvable."; exit 1; }
  echo "rest-server : $BIN"
  restic version
  "$BIN" --version || true

  echo "==> Service fourni par le paquet (restic-rest-server.service) : arrêté et désactivé (on utilise le nôtre)"
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

trouver_disque() {  # affiche /dev/sdX du disque dont le n° de série SMART est SERIE_DISQUE
  local d info
  for d in /sys/block/sd*; do
    d="/dev/$(basename "$d")"
    info="$(smartctl -i -d sat "$d" 2>/dev/null || true)"
    if grep -qE "^Serial Number: +${SERIE_DISQUE}$" <<<"$info"; then
      echo "$d"; return 0
    fi
  done
  return 1
}

disque() {
  echo "==> Recherche du disque n° ${SERIE_DISQUE} (par SMART, pas par nom /dev/sdX)"
  local DEV PART UUID
  DEV="$(trouver_disque)" || { echo "ERREUR : disque ${SERIE_DISQUE} introuvable (boîtier allumé ? câble ?)."; exit 1; }
  echo "Disque trouvé : ${DEV}"
  # Garde-fou : jamais le disque qui porte le système
  local montages
  montages="$(lsblk -no MOUNTPOINTS "$DEV")"
  if grep -qE '^/(boot.*)?$' <<<"$montages"; then
    echo "ERREUR : ${DEV} porte le système. Abandon."; exit 1
  fi
  lsblk -o NAME,SIZE,TYPE,TRAN,FSTYPE,LABEL,MOUNTPOINTS "$DEV"

  PART="$(blkid -t LABEL="$ETIQUETTE" -o device | grep "^${DEV}" || true)"
  if [[ -n "$PART" ]]; then
    echo "Partition '${ETIQUETTE}' déjà présente (${PART}) : PAS de formatage."
  else
    if [[ -n "$(lsblk -no FSTYPE "$DEV" | tr -d '[:space:]')" ]] || [[ $(lsblk -no NAME "$DEV" | wc -l) -gt 1 ]] \
       || [[ -n "$(wipefs -n "$DEV" 2>/dev/null)" ]]; then
      echo "ERREUR : ${DEV} contient déjà des partitions ou des données inconnues. Abandon (rien n'a été modifié)."; exit 1
    fi
    echo
    echo "!!! ${DEV} (n° ${SERIE_DISQUE}) va être ENTIÈREMENT EFFACÉ puis formaté en ext4 '${ETIQUETTE}'."
    read -r -p "Taper EFFACER pour continuer : " rep
    [[ "$rep" == "EFFACER" ]] || { echo "Abandon (rien n'a été modifié)."; exit 1; }
    echo "==> Table GPT + une partition sur tout le disque"
    parted -s "$DEV" mklabel gpt mkpart "$ETIQUETTE" ext4 1MiB 100%
    udevadm settle
    PART="${DEV}1"
    echo "==> ext4 : étiquette ${ETIQUETTE}, 0 % réservé à root, 1 inode par Mo (gros fichiers restic)"
    mkfs.ext4 -L "$ETIQUETTE" -m 0 -T largefile "$PART"
    udevadm settle
  fi

  UUID="$(blkid -s UUID -o value "$PART")"
  [[ -n "$UUID" ]] || { echo "ERREUR : UUID illisible sur ${PART}."; exit 1; }
  echo "UUID : ${UUID}"

  echo "==> Point de montage ${POINT_MONTAGE} (verrouillé quand le disque est absent)"
  if ! mountpoint -q "$POINT_MONTAGE"; then
    [[ -d "$POINT_MONTAGE" ]] || install -d -m 755 "$POINT_MONTAGE"
    chattr +i "$POINT_MONTAGE"   # dossier vide immuable : rien ne peut y écrire si le disque n'est pas monté
  fi

  echo "==> /etc/fstab (par UUID, nofail : le N100 démarre même sans le disque)"
  if grep -q "$UUID" /etc/fstab; then
    echo "Ligne déjà présente : inchangée."
  else
    cp -a /etc/fstab "/etc/fstab.avant-sauvegardes-$(date +%F)"
    echo "UUID=${UUID}  ${POINT_MONTAGE}  ext4  defaults,noatime,nofail,x-systemd.device-timeout=15s  0  2  # disque de sauvegarde (ADR-027)" >> /etc/fstab
  fi
  systemctl daemon-reload
  mountpoint -q "$POINT_MONTAGE" || mount "$POINT_MONTAGE"
  findmnt "$POINT_MONTAGE"
  df -h "$POINT_MONTAGE"

  echo "==> Dossier du dépôt (propriétaire : restic)"
  install -d -m 700 -o restic -g restic "$DEPOT"
  ls -la "$POINT_MONTAGE"

  echo "==> Démarrage de rest-server"
  systemctl restart rest-server.service
  sleep 2
  systemctl status rest-server.service --no-pager
  ss -tlnp | grep ":${PORT} " || { echo "ERREUR : rest-server n'écoute pas sur ${PORT}."; exit 1; }
}

# restic en utilisateur « restic » (les fichiers du dépôt doivent rester à lui, sinon rest-server ne peut plus les lire)
restic_coffre() {
  runuser -u restic -- env RESTIC_CACHE_DIR=/var/cache/restic-entretien \
    restic -r "$DEPOT_PROD01" --password-file "$MDP_PROD01" "$@"
}

entretien_installer() {
  echo "==> Mot de passe restic du dépôt prod-01 (« restic – dépôt prod-01 » du gestionnaire)"
  install -d -m 750 -o root -g restic /etc/restic
  if [[ -s "$MDP_PROD01" ]]; then
    echo "Déjà présent : inchangé."
  else
    local a b
    while true; do
      read -r -s -p "Mot de passe restic : " a; echo
      read -r -s -p "Confirmer : " b; echo
      [[ -n "$a" && "$a" == "$b" ]] && break
      echo "Vide ou différent, recommencer."
    done
    ( umask 027; printf '%s' "$a" > "$MDP_PROD01" )
  fi
  chown root:restic "$MDP_PROD01"; chmod 640 "$MDP_PROD01"
  install -d -m 700 -o restic -g restic /var/cache/restic-entretien
  install -d -m 755 "$ETAT"

  echo "==> Vérification : le mot de passe ouvre-t-il le dépôt ?"
  restic_coffre snapshots

  echo "==> Copie du script dans ${CIBLE}"
  install -m 750 -o root -g root "$0" "$CIBLE"

  echo "==> Service et timer : chaque dimanche à 5 h"
  cat > /etc/systemd/system/entretien-sauvegardes.service <<EOF
# Géré par prod-01/scripts/coffre-sauvegardes.sh — ADR-027, ADR-030
[Unit]
Description=Entretien du dépôt restic prod-01 : tri + contrôle d'intégrité (ADR-030)
RequiresMountsFor=${POINT_MONTAGE}
ConditionPathIsMountPoint=${POINT_MONTAGE}

[Service]
Type=oneshot
ExecStart=${CIBLE} entretien
Nice=10
IOSchedulingClass=idle
EOF
  cat > /etc/systemd/system/entretien-sauvegardes.timer <<EOF
# Géré par prod-01/scripts/coffre-sauvegardes.sh — ADR-030
[Unit]
Description=Entretien hebdomadaire du dépôt restic (dimanche 5 h)

[Timer]
OnCalendar=Sun *-*-* 05:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now entretien-sauvegardes.timer
  systemctl list-timers entretien-sauvegardes.timer --no-pager
}

entretien() {
  mountpoint -q "$POINT_MONTAGE" || { echo "ERREUR : ${POINT_MONTAGE} n'est pas monté."; exit 1; }
  echo "$(date -Is) en-cours" > "${ETAT}/derniere-tentative"
  local echec=0
  echo "==> Tri : ${RETENTION[*]}"
  restic_coffre forget --host "$UTILISATEUR_REST" "${RETENTION[@]}" --prune || echec=1
  echo "==> Contrôle complet (relit toutes les données)"
  restic_coffre check --read-data || echec=1
  if [[ $echec -eq 0 ]]; then
    echo "$(date -Is) ok" > "${ETAT}/derniere-tentative"
    date -Is > "${ETAT}/dernier-entretien-reussi"
    echo "Entretien RÉUSSI"
  else
    echo "$(date -Is) echec" > "${ETAT}/derniere-tentative"
    echo "Entretien en ÉCHEC"; exit 1
  fi
}

case "${1:-}" in
  pare-feu)    pare_feu ;;
  rest-server) rest_server ;;
  disque)      disque ;;
  entretien-installer) entretien_installer ;;
  entretien)   entretien ;;
  restic)      shift; restic_coffre "$@" ;;
  *) echo "Usage : sudo bash $0 {pare-feu|rest-server|disque|entretien-installer|entretien|restic …}"; exit 1 ;;
esac
