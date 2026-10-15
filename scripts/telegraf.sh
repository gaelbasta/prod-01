#!/usr/bin/env bash
# =============================================================================
# telegraf.sh — Installe Telegraf comme sur dev-linux (ADR-031) : dépôt InfluxData, token en
# écriture seule, configuration versionnée, mesures d'état, smartctl via sudo.
#
# Prérequis (depuis dev-linux, dossier ~/claude-projects/prod-01) :
#   scp /usr/share/keyrings/influxdata-archive.gpg scripts/telegraf.sh scripts/telegraf-etat.sh \
#       monitoring/telegraf/<machine>.conf <machine>:
#
# Usage (sur la machine, une fois) :  sudo bash ~/telegraf.sh ~/<machine>.conf
# Rejouable : garde le token déjà saisi ; recopie configuration et script d'état, redémarre Telegraf.
# =============================================================================
set -euo pipefail
trap 'echo "ERREUR : arrêt à la ligne $LINENO (commande : $BASH_COMMAND)" >&2' ERR
[[ $EUID -eq 0 ]] || { echo "Lancer avec sudo."; exit 1; }

CONF="${1:?Chemin du fichier de configuration attendu (ex. ~/prod-01.conf)}"
ICI="$(dirname "$0")"
CLE_SOURCE="${ICI}/influxdata-archive.gpg"
CLE="/usr/share/keyrings/influxdata-archive.gpg"
ENV="/etc/default/telegraf"

echo "==> Clé du dépôt InfluxData (copiée depuis dev-linux, pas retéléchargée)"
if [[ ! -s "$CLE" ]]; then
  [[ -s "$CLE_SOURCE" ]] || { echo "ERREUR : $CLE_SOURCE absent (scp depuis dev-linux)."; exit 1; }
  install -m 644 "$CLE_SOURCE" "$CLE"
fi
gpg --show-keys --with-fingerprint "$CLE" 2>/dev/null | grep -E '^(pub|uid| )' || true

echo "==> Dépôt InfluxData (même ligne que dev-linux)"
echo "deb [signed-by=${CLE}] https://repos.influxdata.com/debian stable main" > /etc/apt/sources.list.d/influxdata.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y telegraf
telegraf --version

echo "==> Token InfluxDB (écriture seule) dans ${ENV} — root uniquement"
if grep -q '^INFLUX_TOKEN=.' "$ENV" 2>/dev/null; then
  echo "Token déjà présent : inchangé."
else
  echo "Coller le token « InfluxDB – telegraf-$(hostname) » du gestionnaire (rien ne s'affiche) :"
  while true; do
    read -r -s -p "Token : " a; echo
    read -r -s -p "Confirmer : " b; echo
    [[ -n "$a" && "$a" == "$b" ]] && break
    echo "Vide ou différent, recommencer."
  done
  ( umask 077; printf 'INFLUX_TOKEN=%s\n' "$a" > "$ENV" )
fi
chown root:root "$ENV"; chmod 600 "$ENV"

echo "==> smartctl autorisé à Telegraf via sudo (lecture SMART uniquement)"
# Écrit dans un fichier temporaire, VÉRIFIÉ, puis seulement mis en place : un fichier sudoers
# invalide dans /etc/sudoers.d peut bloquer sudo. Syntaxe compatible sudo-rs (Ubuntu 26.04) :
# pas de « Defaults! » (sudo-rs refuse logfile/syslog/pam_session).
TMP_SUDO="$(mktemp)"
cat > "$TMP_SUDO" <<'EOF'
# Géré par prod-01/scripts/telegraf.sh — ADR-031 : Telegraf lit la santé des disques
Cmnd_Alias TELEGRAF_SMART = /usr/sbin/smartctl, /usr/sbin/nvme
telegraf ALL=(root) NOPASSWD: TELEGRAF_SMART
EOF
if visudo -cf "$TMP_SUDO"; then
  install -m 440 -o root -g root "$TMP_SUDO" /etc/sudoers.d/telegraf-smart
  rm -f "$TMP_SUDO"
else
  rm -f "$TMP_SUDO"; echo "ERREUR : règle sudo invalide, NON installée (sudo intact)."; exit 1
fi

echo "==> Script d'état"
install -m 755 "${ICI}/telegraf-etat.sh" /usr/local/bin/telegraf-etat

echo "==> Test à blanc de la NOUVELLE configuration (une collecte, en utilisateur telegraf, rien n'est envoyé)"
# La configuration n'est mise en place que si ce test réussit : une config invalide ne remplace
# jamais celle qui tourne (Telegraf continue avec l'ancienne).
TMP_CONF="$(mktemp --suffix=.conf)"; install -m 644 "$CONF" "$TMP_CONF"
JOURNAL_TEST="$(mktemp)"
if ! runuser -u telegraf -- telegraf --config "$TMP_CONF" --test > "$JOURNAL_TEST" 2>&1; then
  grep -E 'E!' "$JOURNAL_TEST" || tail -n 20 "$JOURNAL_TEST"
  rm -f "$TMP_CONF" "$JOURNAL_TEST"
  echo "ERREUR : configuration refusée par Telegraf, NON installée (l'ancienne reste en service)."; exit 1
fi
grep -E '^> (etat_systeme|sauvegarde|entretien|coffre|smart_device|http_response|x509_cert|disk,)|E!' "$JOURNAL_TEST" || true
rm -f "$TMP_CONF" "$JOURNAL_TEST"

echo "==> Configuration mise en place"
[[ -f /etc/telegraf/telegraf.conf.origine ]] || cp -a /etc/telegraf/telegraf.conf /etc/telegraf/telegraf.conf.origine
install -m 644 "$CONF" /etc/telegraf/telegraf.conf

echo "==> Démarrage"
systemctl enable telegraf
systemctl restart telegraf
sleep 20
systemctl is-active telegraf
journalctl -u telegraf --since "-1 min" --no-pager | tail -n 15
