# Surveillance : Telegraf → InfluxDB → Grafana → téléphone

**Quoi** : PROD-01 et `pprod-01` envoient leurs mesures toutes les 15 s à InfluxDB (machine Home Assistant) ; Grafana les vérifie chaque minute et, en cas de problème, notifie le téléphone via Home Assistant.
**Mis en service le** : 2026-10-15 (phase 11) · **Décisions** : [ADR-013](../../DECISIONS.md), [ADR-031](../../DECISIONS.md)
**Fichiers** : [`monitoring/telegraf/`](../../monitoring/telegraf/) (une config par serveur) · [`scripts/telegraf.sh`](../../scripts/telegraf.sh) · [`scripts/telegraf-etat.sh`](../../scripts/telegraf-etat.sh) · [`monitoring/grafana/alertes-prod-01.yaml`](../../monitoring/grafana/alertes-prod-01.yaml)

## Comment ça marche

```
PROD-01  ─ Telegraf (15 s) ─┐                                   Home Assistant (192.168.1.26)
  système, disques, NVMe,   │                                   ┌──────────────────────────────┐
  âge de la sauvegarde      ├── token écriture seule ──────────►│ InfluxDB 2.8 :8087           │
pprod-01 ─ Telegraf (15 s) ─┘   (un par serveur)                │   bucket « infrastructure »  │
  système, disques, SMART,                                      │ Grafana : 11 règles « prod-01 »
  coffre, entretien,                                            │   évaluées chaque minute     │
  + PROD-01 vu de l'extérieur                                   │      │ webhook               │
    (PRISM, wiki, Factorydle, cert.)                            │      ▼                       │
                                                                │ automatisation HA → téléphone│
                                                                └──────────────────────────────┘
```

| Où | Quoi |
|---|---|
| InfluxDB `http://192.168.1.26:8087` | tokens `telegraf-prod-01`, `telegraf-pprod-01` (écriture seule sur `infrastructure`) |
| Grafana, **Alerting → Alert rules → dossier `prod-01`** | les 11 règles, groupe `prod-01-1m` |
| Grafana, contact point **« Home Assistant — dev-linux »** | webhook vers HA (adresse secrète, jamais dans Git) — partagé avec dev-linux, à renommer dans le projet HA |
| Gestionnaire de mots de passe | « InfluxDB – telegraf-prod-01 », « InfluxDB – telegraf-pprod-01 » |
| Sur chaque serveur | `/etc/telegraf/telegraf.conf` (copie du repo), `/etc/default/telegraf` (token, root 600), `/etc/sudoers.d/telegraf-smart`, `/usr/local/bin/telegraf-etat` |

## Les alertes

| Règle | Se déclenche si… | Délai | Si pas de données |
|---|---|---|---|
| PROD-01 — plus de données | aucune mesure de PROD-01 depuis 5 min | 2 min | **alerte** |
| pprod-01 — plus de données | aucune mesure de `pprod-01` depuis 5 min | 2 min | **alerte** |
| PROD-01 — sauvegarde en échec | dernière tentative en échec | 1 min | rien (règles ci-dessus) |
| PROD-01 — sauvegarde trop ancienne | dernière réussite > 26 h (ou trace illisible) | 5 min | rien |
| pprod-01 — entretien du coffre | entretien en échec ou > 8 jours | 5 min | rien |
| pprod-01 — coffre indisponible | disque démonté ou rest-server arrêté | 2 min | rien |
| Santé SMART des disques | un disque n'est plus `health_ok` | immédiat | rien |
| Disque presque plein | un volume > 85 % | 10 min | rien |
| App de PROD-01 injoignable | une adresse surveillée ne répond pas `200` (une alerte par adresse, nommée dans le message) | 3 min | rien |
| Certificat *.prod bientôt expiré | wildcard expire dans < 14 jours (renouvellement normal à 30 j) | immédiat | rien |
| Redémarrage requis | `/var/run/reboot-required` présent | 1 h | rien |

Les règles sont aussi décrites, exactement, dans l'export versionné `monitoring/grafana/alertes-prod-01.yaml` (requêtes Flux, seuils, délais, messages).

---

## A. Installation (faite une fois) — ✅ 2026-10-15

1. **Tokens** — InfluxDB → *Load Data → API Tokens → Generate → Custom API Token* : description `telegraf-<serveur>`, bucket `infrastructure` coché en **Write** seulement. Valeur rangée aussitôt dans le gestionnaire (affichée une seule fois).
2. **Installer** (exemple `pprod-01` ; pour PROD-01 : `prod-01.conf`, et rejouer d'abord `sudo bash ~/sauvegarde-prod-01.sh installer` pour le dossier de traces en 711) :
   ```bash
   # dev-linux, dossier ~/claude-projects/prod-01
   scp /usr/share/keyrings/influxdata-archive.gpg scripts/telegraf.sh scripts/telegraf-etat.sh monitoring/telegraf/pprod-01.conf pprod-01:
   # sur le serveur
   sudo bash ~/telegraf.sh ~/pprod-01.conf
   ```
   Le script : clé du dépôt InfluxData **copiée depuis dev-linux** (empreinte `24C9 75CB A61A 024E E1B6 3178 7C3D 5715 9FC2 F927`), dépôt `repos.influxdata.com/debian stable main`, Telegraf (1.40.2 le 2026-10-15), token demandé 2 fois, règle sudo **vérifiée avant installation**, **test à blanc de la configuration avant de la mettre en place**, démarrage.
3. **Vérifier** : `sleep 45; journalctl -u telegraf --since "-1 min" --no-pager | grep -E "E!|W!" | grep -v "Strict environment"` → rien ; InfluxDB → *Data Explorer* → `infrastructure`, `host` = le serveur → des points récents.
4. **Alertes** : créées dans l'interface Grafana (la 1re pas à pas, les autres par *More → Duplicate*), puis exportées (section D).

**Test réel du 2026-10-15** : `sudo systemctl stop telegraf` sur PROD-01 à ~18 h 57 → règle « PROD-01 — plus de données » en alerte à 19 h 03 → notification sur le téléphone vers 19 h 05 (« Grafana - PROD-01 — plus de données » + le message) → `sudo systemctl start telegraf` → retour à Normal. ✅

**Pièges rencontrés** (corrigés dans le repo) :
- Ubuntu 26.04 utilise **sudo-rs** : `Defaults!… !logfile` y est refusé. Toujours vérifier un fichier sudoers (`visudo -cf`) **avant** de le poser dans `/etc/sudoers.d`.
- Telegraf ≥ 1.39 : `commands = [["/usr/local/bin/telegraf-etat"]]` (liste de listes) ; `command = …` est refusé.
- Grafana + Flux : une requête qui finit par `group() |> max()` doit se terminer par `keep(columns: ["_time", "_value"])` (sinon « input data must be a wide series »).

---

## B. Vérifier que tout va bien

- Grafana → *Alerting → Alert rules* → dossier `prod-01` : 11 règles **Normal**.
- Sur un serveur : `systemctl is-active telegraf` et `journalctl -u telegraf -n 30 --no-pager`.
- Ce que voit Telegraf, sans rien envoyer : `sudo runuser -u telegraf -- telegraf --config /etc/telegraf/telegraf.conf --test 2>&1 | grep '^>'`.
- Les mesures maison : `runuser -u telegraf -- /usr/local/bin/telegraf-etat` (ou simplement `/usr/local/bin/telegraf-etat`).

---

## C. Quand une alerte sonne

| Alerte | Premiers gestes |
|---|---|
| **plus de données** | La machine répond-elle ? `ssh <serveur> uptime`. Si oui : `systemctl status telegraf`, `journalctl -u telegraf -n 50` (token refusé = `401`, InfluxDB injoignable = HA éteint). Si non : courant, réseau, écran + clavier. |
| **sauvegarde en échec** | `ssh -t prod-01 'sudo cat /var/lib/sauvegarde-prod-01/derniere-tentative; sudo journalctl -u sauvegarde-prod-01 -n 80 --no-pager'` → l'étape en cause (`prism`, `factorydle`, `k3s`, `restic:<code>`) ; [runbook sauvegarde](sauvegarde-et-restauration.md), section E ; relancer `sudo sauvegarde-prod-01 lancer`. |
| **sauvegarde trop ancienne** | Le timer tourne-t-il ? `systemctl list-timers sauvegarde-prod-01.timer` ; puis comme ci-dessus. |
| **entretien du coffre** | `ssh -t pprod-01 'sudo journalctl -u entretien-sauvegardes -n 80 --no-pager'` ; relancer `sudo systemctl start entretien-sauvegardes`. |
| **coffre indisponible** | Boîtier allumé ? `ssh -t pprod-01 'findmnt /srv/sauvegardes; systemctl status rest-server'` ; `sudo systemctl start rest-server` (monte le disque tout seul). |
| **SMART** | `sudo smartctl -a /dev/nvme0` (PROD-01) ou `sudo smartctl -a -d sat /dev/disk/by-id/usb-ASMT_2115_ACAAEBBB4AA4-0:0` (IronWolf). Un disque qui faiblit = le remplacer **avant** qu'il lâche ; pour l'IronWolf, vérifier aussi que les sauvegardes restent lisibles (`sudo coffre-sauvegardes restic check`). |
| **disque presque plein** | `df -h` puis `sudo du -xh --max-depth=2 <volume> | sort -h | tail` ; LVM a de la place libre (ADR-003, ADR-026) pour agrandir. |
| **app injoignable** | Le message nomme l'adresse. `kubectl --context prod-01 -n <app> get pods` ; `logs deploy/<app> --tail=50` ; [runbook déployer-une-app](deployer-une-app.md). |
| **certificat** | cert-manager bloqué : `kubectl --context prod-01 -n kube-system describe certificate wildcard-prod-tls` ; [runbook HTTPS](https-certificats.md). |
| **redémarrage requis** | Planifier un `sudo reboot` (ADR-018), puis vérifier PRISM, le coffre et que l'alerte retombe. |

Faire taire une alerte pendant une intervention prévue : Grafana → *Alerting → Silences → New silence* (étiquette `grafana_folder` = `prod-01`, durée limitée).

---

## D. Faire évoluer

**Surveiller une nouvelle app de PROD-01** (liste de contrôle d'un nouveau projet, [PLATFORM_STANDARD](../PLATFORM_STANDARD.md)) :
1. Ajouter son adresse de santé à `urls = [...]` dans `monitoring/telegraf/pprod-01.conf` (ex. `"https://<app>.prod.gba-lab.win/healthz"`).
2. Commit + push, puis `scp scripts/telegraf.sh scripts/telegraf-etat.sh monitoring/telegraf/pprod-01.conf pprod-01:` et `sudo bash ~/telegraf.sh ~/pprod-01.conf` sur `pprod-01` (le token est gardé).
3. Rien à faire dans Grafana : la règle « App de PROD-01 injoignable » prend en compte toute adresse surveillée.

**Ajouter un serveur** (ex. la PPROD en phase 14) : nouveau token, nouveau `monitoring/telegraf/<serveur>.conf` (copier le plus proche), section A ; dans Grafana, dupliquer « plus de données » et ajouter le serveur aux règles qui filtrent `r.host`.

**Modifier une règle** : dans l'interface Grafana, puis **ré-exporter** : *Alert rules* → groupe `prod-01-1m` → *Export* → YAML → remplacer `monitoring/grafana/alertes-prod-01.yaml` (garder l'en-tête) → commit.

**Mettre à jour Telegraf** (dépôt InfluxData, non couvert par les mises à jour automatiques) : `sudo apt update && sudo apt install telegraf` sur chaque serveur, puis section B.

---

## E. Revenir en arrière

| Situation | Solution |
|---|---|
| Couper la surveillance d'un serveur | `sudo systemctl disable --now telegraf` (l'alerte « plus de données » sonnera : la mettre en silence) |
| Revenir à la configuration d'origine du paquet | `sudo cp /etc/telegraf/telegraf.conf.origine /etc/telegraf/telegraf.conf && sudo systemctl restart telegraf` |
| Retirer l'accès SMART | `sudo rm /etc/sudoers.d/telegraf-smart` |
| Révoquer un token | InfluxDB → *API Tokens* → le token → *Delete* (le serveur ne peut plus rien écrire ; en recréer un puis rejouer `telegraf.sh` après avoir vidé `/etc/default/telegraf`) |
| Désinstaller | `sudo apt purge telegraf && sudo rm -f /etc/apt/sources.list.d/influxdata.list /etc/default/telegraf /etc/sudoers.d/telegraf-smart /usr/local/bin/telegraf-etat` |
