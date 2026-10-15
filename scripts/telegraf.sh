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
cat > /etc/sudoers.d/telegraf-smart <<'EOF'
# Géré par prod-01/scripts/telegraf.sh — ADR-031 : Telegraf lit la santé des disques
Cmnd_Alias TELEGRAF_SMART = /usr/sbin/smartctl, /usr/sbin/nvme
telegraf ALL=(root) NOPASSWD: TELEGRAF_SMART
Defaults!TELEGRAF_SMART !logfile, !syslog, !pam_session
EOF
chmod 440 /etc/sudoers.d/telegraf-smart
visudo -cf /etc/sudoers.d/telegraf-smart

echo "==> Script d'état et configuration"
install -m 755 "${ICI}/telegraf-etat.sh" /usr/local/bin/telegraf-etat
[[ -f /etc/telegraf/telegraf.conf.origine ]] || cp -a /etc/telegraf/telegraf.conf /etc/telegraf/telegraf.conf.origine
install -m 644 "$CONF" /etc/telegraf/telegraf.conf

echo "==> Test à blanc (une collecte, en utilisateur telegraf, sans rien envoyer)"
runuser -u telegraf -- telegraf --config /etc/telegraf/telegraf.conf --config-directory /etc/telegraf/telegraf.d --test 2>&1 \
  | grep -E '^> (etat_systeme|sauvegarde|entretien|coffre|smart_device|http_response|x509_cert|disk,)|E!' || true

echo "==> Démarrage"
systemctl enable telegraf
systemctl restart telegraf
sleep 20
systemctl is-active telegraf
journalctl -u telegraf --since "-1 min" --no-pager | tail -n 15
