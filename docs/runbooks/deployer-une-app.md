# Déployer une app avec le chart plateforme

**Quoi** : héberger un projet (profil `app` ou `static`) sur PROD-01 avec le chart plateforme, le mettre à jour, revenir en arrière, le retirer. Et faire évoluer le chart lui-même.
**Mis au point le** : 2026-10-10 (phase 5) · **Décisions** : [ADR-005](../../DECISIONS.md), [ADR-021](../../DECISIONS.md), [ADR-022](../../DECISIONS.md), [ADR-023](../../DECISIONS.md)
**Chart** : `oci://ghcr.io/gaelbasta/charts/plateforme` — source [`charts/plateforme/`](../../charts/plateforme/) (valeurs détaillées dans son [README](../../charts/plateforme/README.md))

> Légende : ✅ = fait réellement · 🔜 = pas encore fait en vrai, à valider au premier usage puis corriger ici.
>
> **Premier vrai projet avec données et secrets : PRISM, le 2026-10-11** (image `0.9.0`, chart `0.1.0`, révision 1) — namespace + `ghcr-pull` + `prism-secrets` créés à la main, `helm upgrade --install … --wait --timeout 3m`, volume `prism-data` 1 Gi *Bound*, `/healthz` → 200, `/` → 401 (mot de passe), mises à jour en mode `Recreate` (volume local). Procédure propre au projet : `docs/` du repo PRISM.

## Ce que le chart fait pour toi

| Sans rien écrire | Comment |
|---|---|
| HTTPS avec cadenas valide | certificat wildcard par défaut de Traefik ([https-certificats.md](https-certificats.md)) |
| `http://` → `https://` | redirection globale dans Traefik (code 308) |
| Mises à jour **sans coupure** | pause de 5 s avant l'arrêt de l'ancien pod (`shutdownDelaySeconds`) — mesuré 300/300 requêtes OK |
| Relance automatique si l'app plante | sondes de santé sur `healthPath` |
| Données jamais supprimées par erreur | le volume survit à `helm uninstall` |
| Fautes de frappe refusées | `values.schema.json` + messages en français |

## Accès

`https://<projet>.prod.gba-lab.win` fonctionne sur le LAN **et**, avec Tailscale activé, de l'extérieur — même adresse, rien à faire par app (ADR-033, [runbook](acces-distant-tailscale.md)). Sans Tailscale, en 4G, la connexion échoue : c'est voulu, le nom pointe vers l'IP privée `192.168.1.16` (ADR-009).

---

## A. Prérequis (une fois par poste)

**Connexion à GHCR** — ✅ dev-linux (2026-10-10) · 🔜 PC Windows

Token GitHub **classic** (github.com → Settings → Developer settings → Personal access tokens → Tokens (classic)) :

| Poste | Note du token | Scope | Expiration |
|---|---|---|---|
| dev-linux | `helm-ghcr-dev-linux` | `write:packages` (inclut `read:packages`) | 1 an |
| PC Windows | `helm-ghcr-windows` | `read:packages` (déployer suffit) | 1 an |

```bash
read -rs GH_TOKEN && echo "token chargé (${#GH_TOKEN} caractères)"      # 40 caractères
printf '%s' "$GH_TOKEN" | helm registry login ghcr.io -u gaelbasta --password-stdin   # Login Succeeded
unset GH_TOKEN
```
Sous PowerShell : `helm registry login ghcr.io -u gaelbasta` (le mot de passe est demandé sans écho).
Le token est mémorisé dans `~/.config/helm/registry/config.json` : fichier **sensible**, jamais copié ni versionné. Révocation : `helm registry logout ghcr.io` + suppression du token sur GitHub.

**Envoyer des images** (poste qui construit, donc dev-linux) — ✅ dev-linux (2026-10-10) : Docker a **sa propre** connexion, distincte de celle de Helm : `docker login ghcr.io -u gaelbasta` (token `write:packages`). Token mémorisé non chiffré dans `~/.docker/config.json` : fichier sensible. Exemple complet de construction et publication d'une image : [wiki.md](wiki.md).

## B. Déployer un projet

### 1. Le fichier de valeurs (dans le repo du projet)

```
<projet>/deploy/values-prod.yaml
```
Ne contient **que ce qui change** par rapport aux défauts du chart. En tête, toujours la commande de déploiement avec la **version du chart** :
```yaml
# Déployer : helm upgrade --install prism oci://ghcr.io/gaelbasta/charts/plateforme --version 0.1.0 \
#              -n prism --create-namespace -f deploy/values-prod.yaml --kube-context prod-01 --wait
profile: app
image:
  repository: ghcr.io/gaelbasta/prism
  tag: "1.0.0"                 # entre guillemets, jamais latest
imagePullSecrets: [ghcr-pull]  # image privée (voir étape 2)
host: prism.prod.gba-lab.win
healthPath: /healthz
env:
  TZ: Europe/Paris
secretEnv: [prism-secrets]     # secret scellé dans prod-01/secrets/ (étape 2)
persistence:
  enabled: true
  size: 5Gi
```
Profil `static` : `profile: static`, image nginx + fichiers (base `nginxinc/nginx-unprivileged`, port 8080), pas de `persistence`.

**Commit + push du fichier AVANT de déployer** (ADR-021). Contrôle : `git status --short` vide.

### 2. Les secrets (si besoin) — ✅ scellés dans Git depuis la phase 10 (2026-10-15, ADR-032)

Les secrets d'une app sont des **SealedSecrets** rangés dans le repo **prod-01** (pas dans le repo du projet) : `secrets/prod-01/<projet>/<nom>.yaml`. Valeur d'abord dans le gestionnaire de mots de passe, puis (sur **dev-linux**, dans `~/claude-projects/prod-01`) :
```bash
mkdir -p secrets/prod-01/<projet>
# Accès à une image privée GHCR : token classic « k3s-prod-01-pull » (read:packages, sans expiration,
# le même pour tous les namespaces — ADR-024), une enveloppe PAR namespace :
read -rs GH_TOKEN
kubectl create secret docker-registry ghcr-pull -n <projet> \
  --docker-server=ghcr.io --docker-username=gaelbasta --docker-password="$GH_TOKEN" --dry-run=client -o yaml \
| kubeseal --cert platform/sealed-secrets/prod-01-cert.pem --format yaml > secrets/prod-01/<projet>/ghcr-pull.yaml
unset GH_TOKEN
# Variables secrètes de l'app (une clé = une variable d'environnement) :
read -rs VALEUR
printf '%s' "$VALEUR" | kubectl create secret generic <projet>-secrets -n <projet> \
  --from-file=MA_VARIABLE=/dev/stdin --dry-run=client -o yaml \
| kubeseal --cert platform/sealed-secrets/prod-01-cert.pem --format yaml > secrets/prod-01/<projet>/<projet>-secrets.yaml
unset VALEUR
git add secrets/prod-01/<projet>/ && git commit -m "<projet> : secrets scellés" && git push
kubectl --context prod-01 create namespace <projet>
kubectl --context prod-01 apply -f secrets/prod-01/<projet>/
kubectl --context prod-01 -n <projet> get sealedsecret         # SYNCED True
```
Détails, changement de valeur, pièges : [secrets.md](secrets.md) (B et C).

> *Historique* : jusqu'au 2026-10-15, ces secrets étaient créés à la main (`kubectl create secret …` directement dans le cluster) ; ceux du wiki et de PRISM ont été migrés sans coupure ([secrets.md](secrets.md), D).

### 3. Déployer — ✅ (test `smoke`, 2026-10-10)

```bash
helm upgrade --install <projet> oci://ghcr.io/gaelbasta/charts/plateforme --version 0.1.0 \
  -n <projet> --create-namespace -f deploy/values-prod.yaml --kube-context prod-01 --wait --timeout 3m
```
Même commande pour **chaque mise à jour** (nouvelle version d'image = changer `image.tag` dans le fichier, commit, relancer).

### 4. Vérifier — ✅

```bash
kubectl --context prod-01 -n <projet> get pods,svc,ingress      # pod Running 1/1
curl -sS https://<projet>.prod.gba-lab.win | head -3             # réponse de l'app, certificat valide
curl -sIL http://<projet>.prod.gba-lab.win | grep -E '^(HTTP|Location)'   # 308 → https → 200
helm history <projet> -n <projet> --kube-context prod-01
```
Puis le navigateur du téléphone **en Wi-Fi** : cadenas valide.

**Mesurer l'absence de coupure pendant une mise à jour** (facultatif, ✅ 300/300 le 2026-10-10) :
```bash
( for i in $(seq 1 300); do curl -s -o /dev/null -w '%{http_code}\n' https://<projet>.prod.gba-lab.win; sleep 0.1; done | sort | uniq -c ) &
sleep 2
helm upgrade --install … (la commande de l'étape 3)
wait                                                              # attendu : « 300 200 »
```

**5. Surveiller** (nouveau projet uniquement, ADR-031) : ajouter `https://<projet>.prod.gba-lab.win<healthPath>` à `urls` dans `monitoring/telegraf/pprod-01.conf`, commit + push, puis rejouer `telegraf.sh` sur `pprod-01` ([runbook surveillance](surveillance.md), section D). Si le projet a des données : sa copie cohérente dans `scripts/sauvegarde-prod-01.sh` (PLATFORM_STANDARD, point 6).

**Si le déploiement expire** :
```bash
kubectl --context prod-01 -n <projet> get pods
kubectl --context prod-01 -n <projet> describe pod | tail -20     # ImagePullBackOff = image/tag/secret ; probe failed = healthPath/port
kubectl --context prod-01 -n <projet> logs deploy/<projet> --tail=50
```

## C. Revenir en arrière — ✅ (testé sur k3d le 2026-10-10)

| Situation | Commande |
|---|---|
| La nouvelle version pose problème | `helm rollback <projet> -n <projet> --kube-context prod-01 --wait` → revient à la révision précédente (ajoute une ligne à l'historique, n'efface rien) |
| Revenir à une révision précise | `helm history …` puis `helm rollback <projet> <N> -n <projet> --kube-context prod-01` |
| Retirer l'app (garder les données) | `helm uninstall <projet> -n <projet> --kube-context prod-01` — le volume `<projet>-data` reste |
| Supprimer **aussi** les données | ⚠️ irréversible (vérifier la sauvegarde d'abord) : `kubectl --context prod-01 -n <projet> delete pvc <projet>-data`, puis `kubectl --context prod-01 delete namespace <projet>` |

Après un rollback, **remettre le fichier de valeurs en accord** avec ce qui tourne (revert du commit), sinon le prochain déploiement réinstallera la version fautive.

---

## D. Faire évoluer le chart plateforme

Règle (ADR-023) : **une version publiée n'est jamais republiée.** Toute modification = nouvelle `version` dans `charts/plateforme/Chart.yaml` (`0.1.1` correctif, `0.2.0` nouvelle option).

1. Modifier le chart, augmenter `version`, mettre à jour son README.
2. Contrôler : `helm lint charts/plateforme -f tests/values-smoke-k3d.yaml` puis `helm template smoke charts/plateforme -f tests/values-smoke-k3d.yaml`.
3. **Tester sur k3d** (port 8080 → 80, 8443 → 443 de dev-linux ; `*.localhost` résolu localement) :
   ```bash
   helm upgrade --install smoke charts/plateforme -n smoke --create-namespace \
     -f tests/values-smoke-k3d.yaml --kube-context k3d-dev-local --wait --timeout 3m
   curl -sS http://test.localhost:8080 | head -2
   ```
   + le test de coupure (section B.4, sur `http://test.localhost:8080`) si le changement touche au Deployment.
4. Commit + push (`git status --short` vide).
5. Publier et marquer :
   ```bash
   helm package charts/plateforme -d /tmp
   helm push /tmp/plateforme-<version>.tgz oci://ghcr.io/gaelbasta/charts      # Pushed + Digest
   rm /tmp/plateforme-<version>.tgz
   git tag plateforme-<version> && git push origin plateforme-<version>
   helm show chart oci://ghcr.io/gaelbasta/charts/plateforme --version <version>
   ```
6. Nettoyer k3d : `helm uninstall smoke -n smoke --kube-context k3d-dev-local` et `kubectl --context k3d-dev-local delete namespace smoke`.
7. Les projets passent à la nouvelle version **un par un**, en changeant `--version` dans l'en-tête de leur fichier de valeurs.

| Version | Date | Contenu | Digest |
|---|---|---|---|
| 0.1.0 | 2026-10-10 | profils app/static, HTTPS par défaut, sondes, volume conservé, pause d'arrêt 5 s, schéma | `sha256:8dfa83fc…f6f4078` |

---

## Journal de mise au point (2026-10-10)

| Constat | Cause | Correction |
|---|---|---|
| 1 requête sur 300 en erreur (502/504) pendant chaque mise à jour, sur k3d | l'ancien pod s'arrêtait avant que Traefik l'ait retiré de sa liste | `lifecycle.preStop.sleep` 5 s (natif Kubernetes, fonctionne même sans shell dans l'image) → 300/300, deux fois sur k3d, une fois sur prod-01 |
| Site injoignable en 4G | IP privée, par conception (ADR-009) | activer Tailscale sur l'appareil ([acces-distant-tailscale.md](acces-distant-tailscale.md)) |
| (wiki, prod-01) `Readiness probe failed … connection refused` juste après le démarrage | sonde passée avant que nginx écoute (pas de délai initial pour la sonde de disponibilité) | aucune : sans effet (pod `1/1`, 0 redémarrage) ; délai initial à envisager dans une future version du chart |
