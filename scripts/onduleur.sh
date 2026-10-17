#!/usr/bin/env bash
# =============================================================================
# onduleur.sh — Installe NUT (onduleur Eaton 3S) sur une machine, à partir de son dossier
# onduleur/<machine>/ du repo (ADR-036). Rôle déduit du dossier :
#   - avec ups.conf  → PRIMAIRE (PROD-01) : pilote USB + serveur + minuteur + pare-feu ;
#   - sans ups.conf  → SECONDAIRE (pprod-01) : surveillant seul, obéit au drapeau d'arrêt.
#
# Prérequis (depuis dev-linux, dossier ~/claude-projects/prod-01) :
#   scp -r scripts/onduleur.sh onduleur/<machine> <machine>:
#
# Usage (sur la machine) :  sudo bash ~/onduleur.sh ~/<machine>
# Rejouable : garde les mots de passe déjà saisis (/etc/nut/mots-de-passe.env, root, 600),
# sauvegarde /etc/nut avant chaque passage (/etc/nut.avant-<date>), redémarre NUT.
# =============================================================================
set -euo pipefail
trap 'echo "ERREUR : arrêt à la ligne $LINENO (commande : $BASH_COMMAND)" >&2' ERR
[[ $EUID -eq 0 ]] || { echo "Lancer avec sudo."; exit 1; }

SRC="${1:?Dossier de la machine attendu (ex. ~/prod-01)}"; SRC="${SRC%/}"
[[ -f "$SRC/nut.conf" && -f "$SRC/upsmon.conf" ]] || { echo "ERREUR : $SRC/nut.conf ou upsmon.conf absent."; exit 1; }
[[ "$(basename "$SRC")" == "$(hostname)" ]] || { echo "ERREUR : dossier $(basename "$SRC") ≠ machine $(hostname). Mauvaise machine ?"; exit 1; }
SECRETS="/etc/nut/mots-de-passe.env"

if [[ -f "$SRC/ups.conf" ]]; then ROLE="primaire"; PAQUET="nut"; else ROLE="secondaire"; PAQUET="nut-client"; fi
echo "==> $(hostname) : rôle $ROLE"

echo "==> Paquet $PAQUET (dépôts Ubuntu, mis à jour par unattended-upgrades)"
DEBIAN_FRONTEND=noninteractive apt-get install -y "$PAQUET"

echo "==> Mots de passe NUT (gestionnaire : « NUT – upsmon-<machine> ») dans $SECRETS — root uniquement"
( umask 077; touch "$SECRETS" ); chown root:root "$SECRETS"; chmod 600 "$SECRETS"
for VAR in $(grep -ho '@@MDP_[A-Z0-9_]*@@' "$SRC"/* | tr -d '@' | sort -u); do
  if grep -q "^${VAR}=." "$SECRETS"; then
    echo "$VAR : déjà présent, inchangé."
  else
    COMPTE="upsmon-$(echo "${VAR#MDP_}" | tr 'A-Z_' 'a-z-')"
    echo "Coller le mot de passe du compte $COMPTE (gestionnaire « NUT – $COMPTE » ; lettres et chiffres seulement, 20 caractères ou plus ; rien ne s'affiche) :"
    while true; do
      read -r -s -p "Mot de passe : " a; echo
      read -r -s -p "Confirmer : " b; echo
      [[ "$a" == "$b" && "$a" =~ ^[A-Za-z0-9]{20,}$ ]] && break
      echo "Différent, trop court ou caractère non autorisé : recommencer."
    done
    printf '%s=%s\n' "$VAR" "$a" >> "$SECRETS"
  fi
done

echo "==> Préparation des fichiers (dossier temporaire, mots de passe insérés)"
TMP="$(mktemp -d)"; chmod 700 "$TMP"
for f in "$SRC"/*; do
  n="$(basename "$f")"; cp "$f" "$TMP/$n"
  while IFS='=' read -r VAR VAL; do
    [[ -n "$VAR" ]] && sed -i "s/@@${VAR}@@/${VAL}/g" "$TMP/$n"
  done < "$SECRETS"
  if grep -qE '@@MDP_[A-Z0-9_]*@@' "$TMP/$n"; then rm -rf "$TMP"; echo "ERREUR : mot de passe manquant dans $n, rien n'est installé."; exit 1; fi
done

SAUVEGARDE="/etc/nut.avant-$(date +%Y%m%d-%H%M%S)"
echo "==> Copie de sécurité de /etc/nut → $SAUVEGARDE"
cp -a /etc/nut "$SAUVEGARDE"; chmod 700 "$SAUVEGARDE"

echo "==> Installation dans /etc/nut (root:nut ; 640, script 750)"
for f in "$TMP"/*; do
  n="$(basename "$f")"
  if [[ "$n" == "upssched-cmd" ]]; then mode=750; else mode=640; fi
  install -m "$mode" -o root -g nut "$f" "/etc/nut/$n"
  echo "   /etc/nut/$n"
done
rm -rf "$TMP"

if [[ "$ROLE" == "primaire" ]]; then
  echo "==> Pare-feu : port 3493 (NUT) ouvert à pprod-01 et à la box HA seulement"
  ufw allow from 192.168.1.51 to any port 3493 proto tcp comment 'NUT depuis pprod-01'
  ufw allow from 192.168.1.26 to any port 3493 proto tcp comment 'NUT depuis la box HA'
  echo "==> Redémarrage du serveur NUT"
  systemctl restart nut-server.service
  sleep 2
fi
echo "==> Redémarrage du surveillant"
systemctl restart nut-monitor.service
sleep 5

echo "==> Contrôles"
systemctl is-active nut-monitor.service
if [[ "$ROLE" == "primaire" ]]; then
  echo "État de l'onduleur : $(upsc onduleur@localhost ups.status 2>/dev/null)"
  echo "Machines connectées :"; upsc -c onduleur@localhost 2>/dev/null
else
  echo "État de l'onduleur vu par $(hostname) : $(upsc onduleur@192.168.1.16 ups.status 2>/dev/null)"
fi
echo "Dernières lignes du journal du surveillant :"
journalctl -u nut-monitor.service -n 5 --no-pager -o cat
echo "Terminé. Copie de sécurité : $SAUVEGARDE (retour arrière : docs/runbooks/onduleur.md)."
