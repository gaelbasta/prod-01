#!/bin/sh
# =============================================================================
# telegraf-etat.sh — Mesures d'état propres à PROD-01 / pprod-01, pour Telegraf (ADR-031).
# Lancé par Telegraf (inputs.exec, utilisateur « telegraf », sans droits root) ; écrit sur la
# sortie standard au format « line protocol » d'InfluxDB. Installé dans /usr/local/bin/telegraf-etat.
#
# Mesures (une ligne par sujet, seulement si le sujet existe sur la machine) :
#   etat_systeme   reboot_requis=0|1
#   sauvegarde     (PROD-01)  age_reussite_s, echec=0|1          ← /var/lib/sauvegarde-prod-01/*
#   entretien      (pprod-01) age_reussite_s, echec=0|1          ← /var/lib/entretien-sauvegardes/*
#   coffre         (pprod-01) disque_monte=0|1, rest_server_actif=0|1
# Âge = -1 si la trace est absente ou illisible (à traiter comme une alerte).
# =============================================================================
maintenant=$(date +%s)

# age <fichier contenant une date> → secondes écoulées depuis cette date, ou -1
age() {
  [ -r "$1" ] || { echo -1; return; }
  t=$(date -d "$(head -n 1 "$1" | cut -d' ' -f1)" +%s 2>/dev/null) || { echo -1; return; }
  echo $((maintenant - t))
}

# echec <fichier derniere-tentative> → 0 si « <date> ok », sinon 1
echec() {
  [ -r "$1" ] || { echo 1; return; }
  [ "$(head -n 1 "$1" | cut -d' ' -f2)" = "ok" ] && echo 0 || echo 1
}

[ -f /var/run/reboot-required ] && r=1 || r=0
echo "etat_systeme reboot_requis=${r}i"

d=/var/lib/sauvegarde-prod-01
if [ -d "$d" ]; then
  echo "sauvegarde,depot=prod-01 age_reussite_s=$(age "$d/derniere-reussite")i,echec=$(echec "$d/derniere-tentative")i"
fi

d=/var/lib/entretien-sauvegardes
if [ -d "$d" ]; then
  echo "entretien,depot=prod-01 age_reussite_s=$(age "$d/dernier-entretien-reussi")i,echec=$(echec "$d/derniere-tentative")i"
  mountpoint -q /srv/sauvegardes && m=1 || m=0
  systemctl is-active --quiet rest-server 2>/dev/null && a=1 || a=0
  echo "coffre disque_monte=${m}i,rest_server_actif=${a}i"
fi
