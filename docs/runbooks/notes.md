# Notes : Memos (https://notes.prod.gba-lab.win)

**Quoi** : une app de notes rapides pour poser ses idées (fil chronologique, tags, recherche), sur le PC comme sur le téléphone. C'est **Memos**, une app *tierce* : image publique, aucun code à nous, déployée avec le chart plateforme.
**Mis en service le** : 2026-10-17 (phase 13 bis) · **Décision** : [ADR-035](../../DECISIONS.md)
**Fichiers** : [`apps/notes/values-prod.yaml`](../../apps/notes/values-prod.yaml) · copie nocturne dans [`scripts/sauvegarde-prod-01.sh`](../../scripts/sauvegarde-prod-01.sh) (`copier_notes`) · surveillance dans [`monitoring/telegraf/pprod-01.conf`](../../monitoring/telegraf/pprod-01.conf)

---

## En deux minutes

```
téléphone (PWA, Tailscale) ─┐
PC (navigateur, LAN) ───────┴─► https://notes.prod.gba-lab.win ─► Traefik ─► pod notes (Memos, :5230, utilisateur 10001)
                                                                                 │
                                                       volume notes-data ──► /var/opt/memos
                                                                               ├ memos_prod.db (SQLite, WAL) ← base vivante, PAS sauvegardée telle quelle
                                                                               └ assets/ (pièces jointes, créé à la 1re)
3 h : sauvegarde-prod-01 ─► sqlite3 .backup ─► /var/lib/sauvegarde-prod-01/notes/memos.db ─► restic ─► pprod-01
chaque minute : pprod-01 (Telegraf) ─► /healthz ─► alerte « App de PROD-01 injoignable » si muet
```

| Élément | Valeur (2026-10-17) |
|---|---|
| Image | `docker.io/neosmemo/memos:0.31.0` (publique, version figée, digest `sha256:24c2707d…`) |
| Release Helm / namespace | `notes` / `notes` — chart plateforme **0.2.0**, révision 1 |
| Volume | `notes-data` = `pvc-0ade3a53-b1e7-4517-8074-507de74e0b19`, 2 Gi, monté sur `/var/opt/memos` |
| Santé | `/healthz` → `Service ready.` (sondes Kubernetes + `pprod-01`) |
| Comptes | `gael` (administrateur, gestionnaire « Memos – notes.prod (gael) ») ; **inscription fermée** ; notes **privées** par défaut |
| Accès | LAN + Tailscale (ADR-033), comme toutes les apps ; injoignable sans Tailscale en 4G (voulu) |
| Secrets Kubernetes | aucun (les comptes vivent dans la base) |

---

## A. Installation — ✅ 2026-10-17 (ce qui a réellement été fait)

1. **Valeurs** : `apps/notes/values-prod.yaml` écrit, `git diff`, commit + push (`aaa8adc`).
2. **Contrôle à blanc** (dev-linux, `~/claude-projects/prod-01`) — rien n'est envoyé au cluster :
   ```bash
   helm template notes oci://ghcr.io/gaelbasta/charts/plateforme --version 0.2.0 \
     -n notes -f apps/notes/values-prod.yaml \
     | grep -nE 'image:|containerPort|path: /|MEMOS_|mountPath|claimName|host:|gethomepage.dev/(name|icon)|storage:|memory:'
   ```
   Vu : image `0.31.0`, port 5230, `/healthz` ×2, `MEMOS_*`, `/var/opt/memos`, `notes-data`, tuile « Notes », 2Gi, 64Mi/512Mi.
3. **Déploiement** :
   ```bash
   helm upgrade --install notes oci://ghcr.io/gaelbasta/charts/plateforme --version 0.2.0 \
     -n notes --create-namespace -f apps/notes/values-prod.yaml --kube-context prod-01 --wait
   kubectl --context prod-01 -n notes get pods,pvc,ingress
   kubectl --context prod-01 -n notes logs deploy/notes --tail=20
   curl -s https://notes.prod.gba-lab.win/healthz; echo
   ```
   Vu : `STATUS: deployed`, pod `1/1 Running` en 16 s ; logs `memos: starting as UID:GID 10001:10001`, `database initialized successfully schemaVersion=0.31.8`, `Data directory: /var/opt/memos` ; `Service ready.`
4. **Compte et réglages** (navigateur, **tout de suite après le déploiement** : le premier compte créé devient administrateur) :
   - créer le compte `gael`, mot de passe rangé dans le gestionnaire ;
   - *Paramètres → Système* : interdire l'inscription (« Disallow user registration ») ;
   - *Paramètres → Préférences* : visibilité par défaut **Privé**, langue Français ;
   - fenêtre privée : seulement l'écran de connexion, pas d'inscription ✅ ; tuile « Notes » sur https://home.prod.gba-lab.win, point vert ✅.
5. **Sauvegarde nocturne** : section C1 (commit `37dc6db`).
6. **Surveillance** : `https://notes.prod.gba-lab.win/healthz` ajouté aux `urls` de `monitoring/telegraf/pprod-01.conf` (commit `d35278c`), puis, depuis dev-linux :
   ```bash
   scp scripts/telegraf.sh scripts/telegraf-etat.sh monitoring/telegraf/pprod-01.conf pprod-01:
   ssh pprod-01 'sudo bash ~/telegraf.sh ~/pprod-01.conf'      # invite gael@pprod-01 si en interactif
   ```
   Vu : `http_response … server=https://notes.prod.gba-lab.win/healthz,status_code=200 … result_code=0i` ; Grafana : 5 adresses, toutes **Normal**.
7. **Téléphone** : section E.

---

## B. Vérifier que tout va bien

```bash
kubectl --context prod-01 -n notes get pods                 # 1/1 Running, peu de RESTARTS
curl -s https://notes.prod.gba-lab.win/healthz; echo        # Service ready.
ssh -t prod-01 'sudo journalctl -u sauvegarde-prod-01 --since today --no-pager | grep Notes'
                                                            # Notes : copie OK (…, intégrité ok, N notes)
```
Grafana : la règle « App de PROD-01 injoignable » est **Normal** pour `notes.prod.gba-lab.win/healthz`.

---

## C. Sauvegarder et restaurer

### C1. Ce qui se passe chaque nuit — ✅ 2026-10-17

L'image de Memos n'a pas `sqlite3` : la copie est faite **depuis PROD-01**, comme celle de la base K3s (ADR-035). `sauvegarde-prod-01 lancer`, étape 1 :
- trouve le volume `/var/lib/rancher/k3s/storage/*_notes_notes-data` (exactement un, sinon **échec**) ;
- `sqlite3 memos_prod.db ".backup …"` → `/var/lib/sauvegarde-prod-01/notes/memos.db` (gère le mode WAL : les notes pas encore reportées dans la base principale sont comprises) ;
- `PRAGMA integrity_check` = `ok`, sinon **échec** ; écrit le nombre de notes dans le journal.

restic exclut la base vivante (`memos_prod.db`, `-wal`, `-shm`) et garde le reste du volume (`assets/`).

Installation de la nouvelle version du script (dev-linux puis PROD-01) :
```bash
scp scripts/sauvegarde-prod-01.sh prod-01:~/
ssh prod-01
sudo bash ~/sauvegarde-prod-01.sh installer      # garde les secrets, recopie le script ; le timer reste actif
sudo sauvegarde-prod-01 lancer                   # … Notes : copie OK (148K, intégrité ok, 1 notes) … Sauvegarde RÉUSSIE
sudo sauvegarde-prod-01 restic ls latest | grep -E 'notes'
```
Vu : instantané `c502d578` ; `…/notes/memos.db` présent, `memos_prod.db` **absent** (exclusion) ✅.

### C2. Contrôler une copie sans toucher à Memos — ✅ 2026-10-17

Sur **`gael@prod-01`** :
```bash
sudo sauvegarde-prod-01 restic restore <instantané> --target /tmp/restauration-notes \
  --include /var/lib/sauvegarde-prod-01/notes
R=/tmp/restauration-notes/var/lib/sauvegarde-prod-01/notes/memos.db
sudo sqlite3 "$R" 'PRAGMA integrity_check; SELECT id, content FROM memo;'
sudo cmp /var/lib/sauvegarde-prod-01/notes/memos.db "$R" && echo "IDENTIQUE à la copie de la nuit"   # seulement pour le dernier instantané
```
Vu (`c502d578`) : `Restored 5 / 2 files/dirs`, `ok`, `2|Premier test #essai`, **IDENTIQUE**. (Les numéros de notes ne repartent pas de 1 : normal.)

### C3. Remettre Memos dans l'état d'une sauvegarde — ✅ 2026-10-17 (répétition avec une note témoin)

Toutes les notes écrites **après** l'instantané choisi sont perdues : en garder une copie (étape 2).

1. **Restaurer la copie** dans `/tmp/restauration-notes` (C2, sans le `cmp`).
2. **Arrêter Memos et mettre la base actuelle de côté** (**`gael@prod-01`**) :
   ```bash
   sudo k3s kubectl -n notes scale deploy/notes --replicas=0
   sudo k3s kubectl -n notes wait --for=delete pod -l app.kubernetes.io/name=notes --timeout=60s
   VOL=$(sudo sh -c 'ls -d /var/lib/rancher/k3s/storage/*_notes_notes-data'); echo "$VOL"
   sudo cp -a "$VOL" /root/notes-avant-restauration       # le dossier entier : pas de * (voir Pièges)
   sudo ls -la "$VOL" /root/notes-avant-restauration      # les deux listes doivent être identiques AVANT de continuer
   ```
   Vu : à l'arrêt, Memos ferme proprement sa base : seul `memos_prod.db` reste (pas de `-wal` ni `-shm`).
3. **Poser la base restaurée** :
   ```bash
   R=/tmp/restauration-notes/var/lib/sauvegarde-prod-01/notes/memos.db
   sudo rm -f "$VOL/memos_prod.db" "$VOL/memos_prod.db-wal" "$VOL/memos_prod.db-shm"
   sudo install -m 644 -o 10001 -g 10001 "$R" "$VOL/memos_prod.db"
   sudo ls -la "$VOL"
   ```
4. **Redémarrer et vérifier** :
   ```bash
   sudo k3s kubectl -n notes scale deploy/notes --replicas=1
   sudo k3s kubectl -n notes rollout status deploy/notes --timeout=120s     # successfully rolled out
   curl -s https://notes.prod.gba-lab.win/healthz; echo                     # Service ready.
   ```
   Dans l'app : les notes de l'instantané sont là, celles écrites après ont disparu. Vu le 2026-10-17 : « Premier test #essai » présente, note témoin « À effacer — test de restauration » disparue ✅.
5. **Ménage** : `sudo rm -rf /tmp/restauration-notes /root/notes-avant-restauration` (une fois sûr de ne pas revenir en arrière).

**Revenir à la base d'avant la restauration** (app arrêtée comme à l'étape 2, `$VOL` défini) — le `*` est placé dans `sudo sh -c` (voir Pièges) :
```bash
sudo sh -c 'rm -f "$1"/memos_prod.db*; cp -a /root/notes-avant-restauration/. "$1"/' _ "$VOL"
sudo ls -la "$VOL"
```
puis étape 4.

**Volume perdu** (app réinstallée, nouveau volume vide) : restaurer d'abord tout l'ancien volume pour retrouver `assets/` ([sauvegarde-et-restauration.md](sauvegarde-et-restauration.md), C3), puis remplacer la base par la copie comme ci-dessus.

---

## D. Mettre Memos à jour (manuel)

Memos sort presque chaque mois, souvent avec des **changements cassants** (la 26.10, en rc le 2026-10-09, déplace l'API de `/api/v1` vers `/api` et change le nom des versions : `26.10`, sans `v`). Le passage 0.31.0 → 26.10 est direct selon Memos.

1. Lire les notes de version **et** le guide de mise à jour de Memos (usememos.com/changelog) pour **chaque** version sautée.
2. Sauvegarde à la main, juste avant : `sudo sauvegarde-prod-01 lancer` (sur PROD-01) → `Notes : copie OK`, noter l'instantané.
3. Changer `image.tag` dans `apps/notes/values-prod.yaml` (entre guillemets, jamais `stable`), `git diff`, commit + push.
4. `helm upgrade --install notes …` (même commande que A3), puis logs : la migration de la base doit apparaître sans erreur ; `/healthz` ; l'app.
5. **Retour arrière** : `helm rollback notes -n notes --kube-context prod-01` remet l'ancienne image, **mais pas l'ancienne base** (déjà migrée) → faire aussi C3 avec l'instantané de l'étape 2.

---

## E. Sur le téléphone (PWA, via Tailscale) — ✅ 2026-10-17

1. Tailscale **activé**, puis ouvrir https://notes.prod.gba-lab.win dans **Chrome** et se connecter.
2. Menu **⋮** → « Ajouter à l'écran d'accueil » / « Installer l'application ». L'icône Memos ouvre l'app en plein écran.
3. Testé en 4G (Wi-Fi coupé) : note écrite au téléphone, visible sur le PC ✅ ; Tailscale coupé → l'app ne joint plus le serveur (voulu, ADR-033) ✅.

Ce qui a débloqué l'installation le 2026-10-17 :
- chercher dans le menu **⋮ du navigateur** (en haut à droite de Chrome), **pas** dans le menu de Memos ;
- utiliser **Chrome** : l'équivalent n'a pas été trouvé dans Firefox.

Autres pistes, non nécessaires ce jour-là : faire défiler le menu ⋮ jusqu'en bas, ou ⋮ → **Partager…** → « Ajouter à l'écran d'accueil » ; si l'entrée existe mais qu'aucune icône n'apparaît : *Paramètres → Applications → Chrome → Autorisations* → « Raccourcis sur l'écran d'accueil » (réglage propre à Xiaomi).

---

## F. Revenir en arrière / désinstaller

| Situation | Solution |
|---|---|
| Dernier `helm upgrade` raté | `helm rollback notes -n notes --kube-context prod-01` (+ C3 si la base a été migrée) |
| Retirer Memos (données gardées) | `helm uninstall notes -n notes --kube-context prod-01` — le volume `notes-data` reste. **Puis** retirer `copier_notes` et l'exclusion de `scripts/sauvegarde-prod-01.sh` (sinon chaque nuit est notée en échec) et l'adresse de `monitoring/telegraf/pprod-01.conf` ; commit, puis réinstaller les deux (C1, A6) |
| Effacer aussi les données | `kubectl --context prod-01 -n notes delete pvc notes-data` (irréversible ; restent les sauvegardes) |

---

## Pièges

- **`sudo` et `*`** : `sudo cp "$VOL"/memos_prod.db* …` échoue (`cannot stat … memos_prod.db*`) car c'est le shell de `gael`, avant `sudo`, qui développe le `*`, et il n'a pas le droit de lister `/var/lib/rancher/k3s/storage`. Le 2026-10-17, la mise de côté de C3 a échoué ainsi **sans bloquer la suite** : la base avec la note témoin a été effacée (aucune perte réelle, c'était le but du test). D'où, en C3 : copie du **dossier entier**, contrôle par `ls` **avant** tout `rm`, et `sudo sh -c '…'` dès qu'il faut un `*`.
- **`MEMOS_DATA` explicite** : sans lui, si `/var/opt/memos` n'est pas inscriptible, Memos se rabat **en silence** sur le dossier courant, hors du volume (données perdues au prochain redémarrage). Avec lui, il s'arrête en erreur.
- **Premier compte = administrateur** : créer son compte juste après le premier déploiement, puis fermer l'inscription.
- `Access mode: public` dans les logs : un visiteur non connecté peut voir les notes marquées « publiques ». Notes privées par défaut, inscription fermée.
- Un `helm rollback` ne rétrograde jamais la base (D5).
