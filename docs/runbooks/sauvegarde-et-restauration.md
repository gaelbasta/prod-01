# Sauvegarde et restauration (restic → rest-server sur `pprod-01`)

**Quoi** : chaque nuit, PROD-01 chiffre et envoie ses données (`/etc`, K3s, volumes des apps) au **coffre** `pprod-01`, qui les range sur un disque de 4 To. PROD-01 peut **déposer** mais **jamais effacer** (append-only). Le tri et le contrôle se font sur le coffre, le dimanche.
**Mis en service le** : 2026-10-13/14 (phase 7) · **Décisions** : [ADR-012](../../DECISIONS.md), [ADR-027](../../DECISIONS.md), [ADR-028](../../DECISIONS.md), [ADR-029](../../DECISIONS.md), [ADR-030](../../DECISIONS.md)
**Scripts** : [`scripts/sauvegarde-prod-01.sh`](../../scripts/sauvegarde-prod-01.sh) (PROD-01) · [`scripts/coffre-sauvegardes.sh`](../../scripts/coffre-sauvegardes.sh) (`pprod-01`)

## Comment ça marche

```
PROD-01 (192.168.1.16)                                   pprod-01 (192.168.1.51)
───────────────────────                                   ───────────────────────
timer 3 h → sauvegarde-prod-01 lancer                     rest-server :8000 (--append-only, --private-repos)
  1. PRISM, Factorydle : copies cohérentes                  ↑ seul 192.168.1.16 autorisé (ufw)
  2. K3s : sqlite3 .backup + integrity_check                │ identifiant « prod-01 »
  3. restic backup ── chiffré avant l'envoi ── HTTP ────────┘
  4. trace derniere-reussite                               disque IronWolf 4 To → /srv/sauvegardes
                                                             └ restic/prod-01/  (dépôt 362bcd9d)
                                                           timer dimanche 5 h → coffre-sauvegardes entretien
                                                             forget --prune (14 j / 8 sem / 12 mois / 3 ans)
                                                             check --read-data
```

| Contenu sauvegardé | Exclu (et pourquoi) |
|---|---|
| `/etc` (dont `/etc/rancher/k3s/config.yaml`, `/etc/rancher/node/password`, `/etc/restic`) | — |
| `/var/lib/rancher/k3s/server` (`token`, `tls/`, `cred/`, manifests) | `db/state.db*` vivante (remplacée par la copie), `kine.sock` |
| `/var/lib/rancher/k3s/storage` (volumes des apps) | `prism.sqlite*` vivante (seules les copies de `/data/sauvegardes` sont fiables, ADR-027) ; Factorydle : `*.tmp` (fichiers en cours d'écriture) |
| `/var/lib/sauvegarde-prod-01` (copie de la base K3s, traces) | `/var/lib/rancher/k3s/agent` (images, ~1,6 Go : se retéléchargent) |

## Où sont les secrets

> Restaurer PROD-01 de zéro : la base K3s restaurée contient déjà la clé Sealed Secrets ; sinon, la reposer depuis le gestionnaire **avant** d'installer le contrôleur ([secrets.md](secrets.md), E).

| Secret | Gestionnaire de mots de passe | PROD-01 | `pprod-01` |
|---|---|---|---|
| Mot de passe **restic** (clé de chiffrement — **perdu = sauvegardes illisibles**) | « restic – dépôt prod-01 » (+ ID du dépôt `362bcd9da7`) | `/etc/restic/motdepasse` (root, 600) | `/etc/restic/prod-01.motdepasse` (root:restic, 640) |
| Identifiant **rest-server** `prod-01` | « rest-server pprod-01 – prod-01 » | dans `/etc/restic/prod-01.env` (root, 600) | haché bcrypt dans `/etc/rest-server/.htpasswd` (root:restic, 640) |
| Clé privée **Sealed Secrets** (ouvre les secrets de `secrets/prod-01/` — **perdue = enveloppes illisibles**, ADR-032) | « Sealed Secrets – clé prod-01 » (fichier joint) | secret `kube-system/sealed-secrets-key72g5d`, donc **dans la base K3s** sauvegardée chaque nuit | — |

---

## A. Mise en place (faite une fois) — ✅ 2026-10-13/14

> Règle : chaque script est **commité et poussé avant** d'être copié puis lancé (`scp scripts/<script> <machine>:`).

### A1. Disque de sauvegarde — `pprod-01`

| Élément | Valeur |
|---|---|
| Disque | Seagate IronWolf **ST4000VN006-3CW104**, 4 To, 5 400 tr/min, n° **WW6AR4CY**, firmware SC60 |
| Boîtier | CENMATE 2 baies USB 3.0 (« DAS, no RAID »), puce **ASMedia** 174c:55aa, pilote `uas`, 5 Gb/s ; disque en **baie 1** |
| Branchement | port USB 3 (bleu) du N100 ; apparaît en `/dev/sdb` (le SSD système est `/dev/sda`) — **le nom peut changer**, les scripts utilisent le n° de série et l'UUID |

Santé **avant formatage** (`smartctl -d sat` traverse la puce USB) :
```bash
ssh -t pprod-01 'sudo smartctl -a -d sat /dev/sdb'          # PASSED, 0 secteur réalloué/en attente, 31 °C
ssh -t pprod-01 'sudo smartctl -t short -d sat /dev/sdb'    # 1 min → Completed without error
ssh -t pprod-01 'sudo smartctl -t long -d sat /dev/sdb'     # 463 min → Completed without error (13→14/10)
ssh -t pprod-01 'sudo smartctl -l selftest -d sat /dev/sdb' # lire le résultat
```
Le boîtier n'a **pas** mis le disque en veille pendant le test long. Seagate : `Raw_Read_Error_Rate` / `Seek_Error_Rate` bruts élevés = normal (compteurs internes).

### A2. Coffre — `pprod-01` (invite `gael@pprod-01`)

```bash
sudo bash ~/coffre-sauvegardes.sh pare-feu       # ufw : 22 depuis le LAN, 8000 depuis 192.168.1.16 seul
sudo bash ~/coffre-sauvegardes.sh rest-server    # apt restic + restic-rest-server + apache2-utils ; utilisateur restic ;
                                                 # htpasswd « prod-01 » (saisi 2 fois) ; service rest-server activé, NON démarré
sudo bash ~/coffre-sauvegardes.sh disque         # trouve le disque par n° de série, demande EFFACER, GPT + ext4
                                                 # « sauvegardes » (-m 0 -T largefile), fstab UUID+nofail, chattr +i,
                                                 # /srv/sauvegardes/restic (restic:restic 700), démarre rest-server
sudo bash ~/coffre-sauvegardes.sh entretien-installer   # mot de passe restic (vérifié en ouvrant le dépôt),
                                                        # /usr/local/sbin/coffre-sauvegardes, timer dimanche 5 h activé
```
Relevés : UUID de la partition `d5c73bd1-ea12-45e4-b84b-913af3eb3141`, 3,7 T disponibles. Le paquet Ubuntu nomme la commande `/usr/bin/restic-rest-server` et fournit `restic-rest-server.service` (jamais activé, laissé désactivé).

### A3. Déposant — PROD-01 (invite `gael@prod-01`)

```bash
sudo bash ~/sauvegarde-prod-01.sh installer     # apt restic + sqlite3 ; demande les 2 mots de passe (2 fois chacun) ;
                                                # /usr/local/sbin/sauvegarde-prod-01 ; service + timer (non activé)
sudo sauvegarde-prod-01 initialiser             # restic init → dépôt 362bcd9da7 (version 2, compression)
sudo sauvegarde-prod-01 lancer                  # 1re sauvegarde : 988 fichiers, 23 Mo → 5,6 Mo stockés, 1 s (6a41b315)
sudo sauvegarde-prod-01 activer                 # timer 3 h activé
```
Rejouer `installer` après une modification du script : il **garde** les secrets existants (aucune question) et recopie script et unités systemd.

---

## B. Vérifier que tout va bien

**Depuis dev-linux** (`gael@dev-linux`) :
```bash
ssh -t prod-01  'sudo cat /var/lib/sauvegarde-prod-01/derniere-tentative /var/lib/sauvegarde-prod-01/derniere-reussite; systemctl list-timers sauvegarde-prod-01.timer --no-pager'
ssh -t pprod-01 'cat /var/lib/entretien-sauvegardes/derniere-tentative; findmnt /srv/sauvegardes; systemctl is-active rest-server; df -h /srv/sauvegardes'
ssh -t prod-01  'sudo sauvegarde-prod-01 restic snapshots'
```

| Contrôle | Attendu |
|---|---|
| `derniere-tentative` (PROD-01) | `<date> ok` de la nuit (`echec <étapes>` = à regarder : `journalctl -u sauvegarde-prod-01`) |
| `derniere-reussite` | moins de 26 h (surveillé par Home Assistant en phase 11) |
| Coffre | `/srv/sauvegardes` monté, `active`, place disponible |
| `derniere-tentative` (`pprod-01`) | `<date> ok` du dernier dimanche (`journalctl -u entretien-sauvegardes`) |

`/var/lib/sauvegarde-prod-01` est réservé à root (700 : il contient la copie de la base K3s) → `sudo cat` obligatoire. Première sauvegarde automatique : 2026-10-15 à 3 h 00 (`8f9308e8`, 2,9 Mo stockés, 2 s) ✅.

Journaux : `journalctl -u sauvegarde-prod-01 -n 50` (PROD-01) · `journalctl -u rest-server -n 50` et `journalctl -u entretien-sauvegardes -n 50` (`pprod-01`).

Raccourcis restic : `sudo sauvegarde-prod-01 restic <commande>` sur PROD-01 (via rest-server) · `sudo coffre-sauvegardes restic <commande>` sur `pprod-01` (accès direct, en utilisateur `restic` — **ne jamais lancer restic en root directement sur le dossier du dépôt** : les fichiers créés seraient illisibles pour rest-server).

---

## C. Restaurer

> Toujours **restaurer à côté** (`--target /tmp/…`), comparer, puis copier. Ne jamais restaurer directement par-dessus des fichiers en service.
> Lister ce qu'il y a : `sudo sauvegarde-prod-01 restic snapshots` puis `sudo sauvegarde-prod-01 restic ls <id|latest> | grep <motif>`.

### C1. Un fichier ou un dossier (ex. `/etc`) — testé ✅ 2026-10-14 (test 1)

```bash
sudo sauvegarde-prod-01 restic restore latest --target /tmp/test-restauration-1 --include /etc/rancher/k3s/config.yaml
sudo sha256sum /etc/rancher/k3s/config.yaml /tmp/test-restauration-1/etc/rancher/k3s/config.yaml
sudo cmp /etc/rancher/k3s/config.yaml /tmp/test-restauration-1/etc/rancher/k3s/config.yaml && echo IDENTIQUE
```
Résultat : `Restored 4 / 1 files/dirs` (le fichier + ses 3 dossiers parents), empreintes identiques. Puis copier le fichier à sa place si besoin, et `sudo rm -rf /tmp/test-restauration-1`.

### C2. La base K3s — testé ✅ 2026-10-14 (test 2)

Vérifier une copie :
```bash
sudo sauvegarde-prod-01 restic restore latest --target /tmp/test-restauration-2 --include /var/lib/sauvegarde-prod-01/k3s/state.db
F=/tmp/test-restauration-2/var/lib/sauvegarde-prod-01/k3s/state.db
sudo sqlite3 "$F" 'PRAGMA integrity_check;'                     # ok
sudo sqlite3 "$F" 'SELECT COUNT(*) FROM kine;'                   # 1527 le 2026-10-14
sudo sqlite3 "$F" "SELECT DISTINCT name FROM kine WHERE name LIKE '/registry/namespaces/%';"
```
Résultat : `ok`, namespaces `cert-manager`, `default`, `kube-*`, `prism`, `wiki` présents.

Remettre la base en service (**non testé** — réservé à la reconstruction de PROD-01, phase 17) : arrêter K3s (`sudo systemctl stop k3s`), remplacer `/var/lib/rancher/k3s/server/db/state.db` par la copie restaurée en supprimant `state.db-wal` et `state.db-shm`, restaurer aussi `/var/lib/rancher/k3s/server/token` et `tls/` du **même** instantané, puis `sudo systemctl start k3s`.

### C3. Le volume d'une app — testé ✅ 2026-10-14 (test 3, répétition de sinistre)

Scénario joué avec l'app de test [`tests/values-restauration-prod.yaml`](../../tests/values-restauration-prod.yaml) (nginx qui sert son volume) : preuve aléatoire écrite → sauvegarde `88ceb533` → **app, namespace et volume supprimés** (dossier effacé du disque) → app redéployée (volume neuf, vide) → restauration → preuve relue à l'identique en HTTPS.

Les volumes portent un nom **différent** après recréation (`pvc-<id>_<namespace>_<nom>`) : on restaure l'**ancien** chemin (celui de la sauvegarde) et on copie son **contenu** dans le **nouveau** dossier.

1. **Trouver l'ancien chemin dans la sauvegarde** (PROD-01) :
   ```bash
   sudo sauvegarde-prod-01 restic ls latest | grep '_<namespace>_<volume>$'
   ```
2. **Redéployer l'app si elle n'existe plus** (dev-linux), puis **l'arrêter** pour que personne n'écrive pendant la restauration — indispensable pour une base SQLite (PRISM) :
   ```bash
   helm upgrade --install <app> oci://ghcr.io/gaelbasta/charts/plateforme --version 0.1.0 -n <app> --create-namespace -f deploy/values-prod.yaml --kube-context prod-01
   kubectl --context prod-01 -n <app> scale deploy/<app> --replicas=0
   ```
3. **Restaurer et copier** (PROD-01) :
   ```bash
   ANCIEN=/var/lib/rancher/k3s/storage/pvc-<ancien-id>_<namespace>_<volume>
   NOUVEAU=$(sudo bash -c 'ls -d /var/lib/rancher/k3s/storage/*_<namespace>_<volume>'); echo "$NOUVEAU"
   sudo sauvegarde-prod-01 restic restore <id-instantané> --target /tmp/restauration --include "$ANCIEN"
   sudo cp -a "/tmp/restauration$ANCIEN/." "$NOUVEAU/"
   sudo ls -la "$NOUVEAU"
   ```
4. **Redémarrer l'app et vérifier** (dev-linux) : `kubectl --context prod-01 -n <app> scale deploy/<app> --replicas=1`, pod `1/1`, données visibles dans l'app.
5. Nettoyer : `sudo rm -rf /tmp/restauration`.

**PRISM** : ne jamais remettre `prism.sqlite` tel quel (il n'est pas sauvegardé) : restaurer le volume, puis remplacer `prism.sqlite` par la copie voulue de `/data/sauvegardes/prism-AAAA-MM-JJ.sqlite` (app arrêtée, sans `-wal`/`-shm`) — procédure à confirmer dans la doc du projet PRISM.

Relevés du test 3 : ancien volume `pvc-ca803ca3-…`, nouveau `pvc-ab15984d-…`, `Restored 8 / 3 files/dirs`, preuve `c06DYyzuPZxlWSUG` identique avant et après.

### C3 bis. Une partie de Factorydle — testé ✅ 2026-10-16 (partie d'essai)

Factorydle garde ses parties en fichiers JSON dans son volume (`/data`). Chaque nuit, `serveur/sauvegarder.ts` en fait une **copie cohérente** dans `/data/nocturne/` (parties, copies du jour, corbeille, `index.json`) : c'est elle qui fait foi. Les fichiers vivants sont aussi sauvegardés (écriture atomique), sauf les `*.tmp`. Procédure complète, y compris remettre une partie en jeu : `docs/exploitation.md` du repo Factorydle.

Test du 2026-10-16 (sur PROD-01, après `sudo sauvegarde-prod-01 lancer` → instantané `580c846d`) :
```bash
VOL=/var/lib/rancher/k3s/storage/pvc-646730b2-1d56-4301-90ff-8a78a7fe9733_factorydle_factorydle-data
sudo sauvegarde-prod-01 restic restore latest --target /tmp/restauration-factorydle --include "$VOL/nocturne"
sudo diff -r "$VOL/nocturne" "/tmp/restauration-factorydle$VOL/nocturne" && echo "IDENTIQUE à la copie de la nuit"
sudo sh -c "grep -l 'Essai PROD' /tmp/restauration-factorydle$VOL/nocturne/parties/*"
sudo rm -rf /tmp/restauration-factorydle
```
Résultat : `Restored 14 / 8 files/dirs`, **IDENTIQUE à la copie de la nuit** (qui contenait la partie « Essai PROD »).

> **Piège** : un `*` dans un chemin restauré doit être placé **à l'intérieur** de `sudo sh -c '…'`. Sinon c'est ton shell (utilisateur `gael`) qui essaie de le développer avant `sudo`, n'a pas le droit de lister le dossier (propriété de root), et la commande échoue avec `No such file or directory`.

### C4. Depuis le coffre, si PROD-01 est perdu

Sur `pprod-01`, accès direct au dépôt (en utilisateur `restic`) : `sudo coffre-sauvegardes restic snapshots`, puis `sudo coffre-sauvegardes restic restore <id> --target /tmp/<dossier> …` (`/tmp/<dossier>` appartiendra à `restic`). Depuis une **nouvelle** machine : installer restic, mot de passe « restic – dépôt prod-01 », `restic -r rest:http://192.168.1.51:8000/prod-01/` avec l'identifiant rest-server (ouvrir le port 8000 à sa nouvelle IP dans ufw) — à dérouler en phase 17.

---

## D. Garde-fous vérifiés le 2026-10-14

| Garde-fou | Test | Résultat |
|---|---|---|
| Seul PROD-01 joint le coffre | `curl -m 5 http://192.168.1.51:8000/` depuis PROD-01 puis dev-linux (rest-server arrêté) | PROD-01 : refus immédiat (code 7) ; dev-linux : délai dépassé (code 28) ✅ |
| Append-only | `restic forget 6a41b315` lancé sur PROD-01 (équivalent : `sudo sauvegarde-prod-01 restic forget 6a41b315`) | `403 Forbidden`, instantané conservé ✅ — **restic rend code 0 malgré tout** |
| Disque absent → rien n'écrit sur le SSD | `systemctl stop rest-server`, `umount /srv/sauvegardes`, boîtier éteint, puis `sudo touch /srv/sauvegardes/test` et `sudo systemctl start rest-server` | `touch` refusé même en root (`chattr +i`) ; `A dependency job for rest-server.service failed` ; port 8000 fermé ✅ |
| Retour automatique | boîtier rallumé, `sudo reboot` de `pprod-01` | disque monté par UUID, rest-server `active`, port 8000 en écoute ✅ |
| Entretien sans casser les droits | `sudo systemctl start entretien-sauvegardes` puis `sudo find /srv/sauvegardes/restic ! -user restic` | `no errors were found`, aucun fichier hors `restic` ✅ |

---

## E. Revenir en arrière / dépanner

| Situation | Solution |
|---|---|
| Sauvegarde de la nuit en échec | `journalctl -u sauvegarde-prod-01 -n 80` ; `derniere-tentative` indique l'étape (`prism`, `k3s`, `restic:<code>`) ; relancer à la main `sudo sauvegarde-prod-01 lancer` |
| `restic` : `401 Unauthorized` | identifiant rest-server différent entre `/etc/restic/prod-01.env` (PROD-01) et `.htpasswd` (`pprod-01`) : supprimer `prod-01.env` puis rejouer `installer`, ou recréer l'identifiant (`sudo htpasswd -B /etc/rest-server/.htpasswd prod-01` puis `sudo systemctl restart rest-server`) |
| `restic` : connexion refusée / délai | `pprod-01` éteint, boîtier éteint (rest-server ne démarre pas sans disque) ou pare-feu : `ssh -t pprod-01 'findmnt /srv/sauvegardes; systemctl status rest-server'` |
| Boîtier rallumé après coupure, disque non monté | `sudo systemctl start rest-server` (monte le disque tout seul grâce à `RequiresMountsFor`) ou `sudo reboot` |
| `restic` : `repository is already locked` | une autre opération tourne (sauvegarde ou entretien) ; si elle est morte : `sudo coffre-sauvegardes restic unlock` sur `pprod-01` |
| Arrêter les sauvegardes nocturnes | `sudo systemctl disable --now sauvegarde-prod-01.timer` (PROD-01) ; réactiver : `sudo sauvegarde-prod-01 activer` |
| Retirer le disque proprement | `sudo systemctl stop rest-server` puis `sudo umount /srv/sauvegardes`, puis éteindre le boîtier |
| Annuler la ligne fstab | `sudo cp /etc/fstab.avant-sauvegardes-2026-10-14 /etc/fstab && sudo systemctl daemon-reload` |
| Supprimer le verrou du point de montage (disque démonté) | `sudo chattr -i /srv/sauvegardes` |
| Mot de passe restic perdu | **aucune solution** : les sauvegardes sont illisibles. D'où la copie obligatoire dans le gestionnaire (ADR-027) |
