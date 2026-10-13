#!/usr/bin/env bash
# =============================================================================
# sauvegarde-prod-01.sh — Sauvegarde nocturne de PROD-01 avec restic,
# vers le rest-server append-only de pprod-01 (ADR-012, ADR-027, ADR-028).
#
# Usage (sur PROD-01, une sous-commande à la fois) :
#   sudo bash sauvegarde-prod-01.sh installer    # paquets, secrets, copie du script, service + timer (timer NON activé)
#   sudo sauvegarde-prod-01 initialiser          # crée le dépôt restic (une seule fois, disque de pprod-01 monté)
#   sudo sauvegarde-prod-01 lancer               # une sauvegarde complète (c'est ce que lance le timer)
#   sudo sauvegarde-prod-01 activer              # active le timer nocturne (après une 1re sauvegarde réussie)
#
# Ce que fait « lancer » :
#   1. copie cohérente de chaque app qui en a une (PRISM : contrat ADR-027) ;
#   2. copie cohérente de la base K3s (sauvegarde en ligne SQLite) + contrôle d'intégrité ;
#   3. restic backup : /etc, /var/lib/rancher/k3s/server (token, tls… ; base vivante exclue),
#      /var/lib/rancher/k3s/storage (volumes ; bases vivantes exclues), copies du point 2 ;
#      /var/lib/rancher/k3s/agent (images) n'est PAS sauvegardé : il se retélécharge ;
#   4. trace de la dernière tentative / réussite dans /var/lib/sauvegarde-prod-01 (Home Assistant, phase 11).
# Une étape en échec n'empêche pas les suivantes, mais la sauvegarde est notée en ÉCHEC (code ≠ 0).
#
# Secrets (jamais dans Git, ADR-008) — tous aussi dans le gestionnaire de mots de passe :
#   /etc/restic/motdepasse    mot de passe restic (« restic – dépôt prod-01 »)
#   /etc/restic/prod-01.env   dépôt + identifiant rest-server (« rest-server pprod-01 – prod-01 »)
# =============================================================================
set -euo pipefail
trap 'echo "ERREUR : arrêt à la ligne $LINENO (commande : $BASH_COMMAND)" >&2' ERR

[[ $EUID -eq 0 ]] || { echo "Lancer avec sudo."; exit 1; }

DEPOT="rest:http://192.168.1.51:8000/prod-01/"
UTILISATEUR_REST="prod-01"
DIR_SECRETS="/etc/restic"
FICHIER_MDP="${DIR_SECRETS}/motdepasse"
FICHIER_ENV="${DIR_SECRETS}/prod-01.env"
ETAT="/var/lib/sauvegarde-prod-01"          # copies cohérentes + traces
COPIE_K3S="${ETAT}/k3s/state.db"
BASE_K3S="/var/lib/rancher/k3s/server/db/state.db"
CIBLE="/usr/local/sbin/sauvegarde-prod-01"  # copie installée (celle que lance le timer)
HEURE="03:00"                               # heure de la sauvegarde nocturne

journal() { echo "[$(date '+%F %T')] $*"; }

lire_secret() {  # lire_secret "<invite>" -> saisie masquée, demandée deux fois
  local a b
  while true; do
    read -r -s -p "$1 : " a; echo >&2
    read -r -s -p "Confirmer : " b; echo >&2
    [[ -n "$a" && "$a" == "$b" ]] && { printf '%s' "$a"; return; }
    echo "Vide ou différent, recommencer." >&2
  done
}

charger_env() {
  [[ -s "$FICHIER_ENV" ]] || { echo "ERREUR : $FICHIER_ENV absent (lancer d'abord « installer »)."; exit 1; }
  set -a; . "$FICHIER_ENV"; set +a
}

# --------------------------------------------------------------------------- installer
installer() {
  journal "==> Paquets Ubuntu (ADR-028)"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y restic sqlite3
  restic version
  sqlite3 --version

  journal "==> Secrets dans ${DIR_SECRETS} (root uniquement)"
  install -d -m 700 -o root -g root "$DIR_SECRETS"
  if [[ -s "$FICHIER_MDP" ]]; then
    echo "Mot de passe restic déjà présent : inchangé."
  else
    echo "Coller le mot de passe « restic – dépôt prod-01 » du gestionnaire (rien ne s'affiche) :"
    ( umask 077; lire_secret "Mot de passe restic" > "$FICHIER_MDP" )
  fi
  if [[ -s "$FICHIER_ENV" ]]; then
    echo "Fichier ${FICHIER_ENV} déjà présent : inchangé."
  else
    echo "Coller le mot de passe « rest-server pprod-01 – prod-01 » du gestionnaire (rien ne s'affiche) :"
    local mdp_rest
    mdp_rest="$(lire_secret "Mot de passe rest-server")"
    # %q protège les caractères spéciaux du mot de passe ($, `, ", espaces…)
    ( umask 077
      {
        echo "# Généré par sauvegarde-prod-01.sh installer — ADR-027, ADR-029. NE PAS COMMITER."
        printf 'RESTIC_REPOSITORY=%q\n'    "$DEPOT"
        printf 'RESTIC_PASSWORD_FILE=%q\n' "$FICHIER_MDP"
        printf 'RESTIC_REST_USERNAME=%q\n' "$UTILISATEUR_REST"
        printf 'RESTIC_REST_PASSWORD=%q\n' "$mdp_rest"
        printf 'RESTIC_CACHE_DIR=%q\n'     "/var/cache/restic"
      } > "$FICHIER_ENV" )
  fi
  chmod 600 "$FICHIER_MDP" "$FICHIER_ENV"

  journal "==> Copie du script dans ${CIBLE}"
  install -m 750 -o root -g root "$0" "$CIBLE"
  install -d -m 700 "$ETAT" "${ETAT}/k3s"

  journal "==> Service et timer systemd (timer NON activé)"
  cat > /etc/systemd/system/sauvegarde-prod-01.service <<EOF
# Géré par prod-01/scripts/sauvegarde-prod-01.sh — ADR-027
[Unit]
Description=Sauvegarde restic de PROD-01 vers pprod-01 (ADR-027)
Wants=network-online.target
After=network-online.target k3s.service

[Service]
Type=oneshot
ExecStart=${CIBLE} lancer
Nice=10
IOSchedulingClass=idle
EOF
  cat > /etc/systemd/system/sauvegarde-prod-01.timer <<EOF
# Géré par prod-01/scripts/sauvegarde-prod-01.sh — ADR-027
[Unit]
Description=Sauvegarde nocturne de PROD-01 (${HEURE})

[Timer]
OnCalendar=*-*-* ${HEURE}:00
# Machine éteinte à l'heure prévue : la sauvegarde part au démarrage suivant
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  journal "Installé. Suite : « sudo sauvegarde-prod-01 initialiser » (disque de pprod-01 monté)."
}

# --------------------------------------------------------------------------- initialiser
initialiser() {
  charger_env
  if restic cat config >/dev/null 2>&1; then
    echo "Le dépôt existe déjà : rien à faire."
  else
    restic init
  fi
  restic cat config
}

# --------------------------------------------------------------------------- lancer
lancer() {
  charger_env
  local echecs=() code
  journal "Début de la sauvegarde"
  echo "$(date -Is) en-cours" > "${ETAT}/derniere-tentative"

  journal "==> 1. Copies cohérentes des apps"
  # PRISM (contrat ADR-027) : code 0 = copie écrite et relue dans /data/sauvegardes
  if k3s kubectl -n prism exec deploy/prism -- node src/serveur/sauvegarder.ts; then
    journal "PRISM : copie OK"
  else
    journal "PRISM : ÉCHEC de la copie cohérente"; echecs+=("prism")
  fi

  journal "==> 2. Copie cohérente de la base K3s"
  rm -f "$COPIE_K3S"
  if sqlite3 "$BASE_K3S" ".backup '${COPIE_K3S}'" \
     && [[ "$(sqlite3 "$COPIE_K3S" 'PRAGMA integrity_check;')" == "ok" ]]; then
    journal "Base K3s : copie OK ($(du -h "$COPIE_K3S" | cut -f1), intégrité ok)"
  else
    journal "Base K3s : ÉCHEC"; echecs+=("k3s")
  fi

  journal "==> 3. restic backup"
  code=0
  restic backup --tag nocturne \
    --exclude "${BASE_K3S}" --exclude "${BASE_K3S}-wal" --exclude "${BASE_K3S}-shm" \
    --exclude "/var/lib/rancher/k3s/server/kine.sock" \
    --exclude "/var/lib/rancher/k3s/storage/*_prism_prism-data/prism.sqlite*" \
    /etc /var/lib/rancher/k3s/server /var/lib/rancher/k3s/storage "$ETAT" \
    || code=$?
  # 0 = OK ; 3 = instantané créé mais des fichiers illisibles ; autre = pas d'instantané
  if [[ $code -ne 0 ]]; then journal "restic : ÉCHEC (code $code)"; echecs+=("restic:$code"); fi

  journal "==> 4. Trace"
  if [[ ${#echecs[@]} -eq 0 ]]; then
    echo "$(date -Is) ok" > "${ETAT}/derniere-tentative"
    date -Is > "${ETAT}/derniere-reussite"
    journal "Sauvegarde RÉUSSIE"
  else
    echo "$(date -Is) echec ${echecs[*]}" > "${ETAT}/derniere-tentative"
    journal "Sauvegarde en ÉCHEC : ${echecs[*]}"
    exit 1
  fi
}

# --------------------------------------------------------------------------- activer
activer() {
  systemctl enable --now sauvegarde-prod-01.timer
  systemctl list-timers sauvegarde-prod-01.timer --no-pager
}

case "${1:-}" in
  installer)   installer ;;
  initialiser) initialiser ;;
  lancer)      lancer ;;
  activer)     activer ;;
  *) echo "Usage : sudo $0 {installer|initialiser|lancer|activer}"; exit 1 ;;
esac
