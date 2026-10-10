# Wiki : construire, publier, mettre à jour

**Quoi** : le wiki `https://wiki.prod.gba-lab.win` (LAN) rassemble la doc Markdown des repos listés dans le repo **wiki**, la transforme en site (MkDocs 1.6, thème readthedocs) et la sert avec nginx sur PROD-01 (chart plateforme, profil `static`).
**Mis en service le** : 2026-10-10 (phase 6) · **Décisions** : [ADR-011](../../DECISIONS.md), [ADR-024](../../DECISIONS.md), [ADR-023](../../DECISIONS.md)
**Repo** : `github.com/gaelbasta/wiki` (privé) — copie de travail `~/claude-projects/wiki` sur **dev-linux** · **Image** : `ghcr.io/gaelbasta/wiki` (privée)

> Tout ce qui suit se fait sur **dev-linux** (invite `gael@dev-linux`) : la construction télécharge les repos avec la clé SSH GitHub de ce poste.

## Comment ça marche

```
projets.txt ──► scripts/construire.sh ──► image ghcr.io/gaelbasta/wiki:<AAAA.MM.JJ-HHMM> ──► docker push ──► helm upgrade
 (liste des      1. git clone de chaque repo depuis GitHub (branche main)
  repos)         2. copie des .md (ou de tout le repo) dans build/docs/<nom>/
                 3. docker build : MkDocs → site HTML → nginx
```

- La doc publiée est celle **poussée sur GitHub**, jamais une copie locale : **toujours `git push` la doc avant de reconstruire**.
- Le wiki **ne se met pas à jour tout seul** : après une modification de doc, refaire la section B.
- Menu : ordre des lignes de `projets.txt` pour les onglets ; dans chaque repo, un fichier `.nav.yml` (facultatif) par dossier fixe l'ordre des pages (section E).

---

## A. Mise en place (faite une fois) — ✅ 2026-10-10

1. Repo GitHub `wiki` créé **privé, vide** ; clone dans `~/claude-projects/wiki`, contenu ajouté, `git branch -M main`, `git push -u origin main`.
2. **Docker connecté à GHCR** sur dev-linux (distinct de la connexion Helm) — token classic `write:packages` :
   ```bash
   docker login ghcr.io -u gaelbasta          # coller le token (rien ne s'affiche) → Login Succeeded
   ```
   Le token est mémorisé **non chiffré** dans `~/.docker/config.json` (avertissement normal) : fichier sensible, jamais copié.
3. **Accès du cluster aux images privées** (premier usage réel de l'étape B.2 de [deployer-une-app.md](deployer-une-app.md)) — token classic **`k3s-prod-01-pull`**, scope `read:packages` seul, **sans expiration**, rangé dans le gestionnaire de mots de passe :
   ```bash
   kubectl --context prod-01 create namespace wiki
   read -rs GH_TOKEN && echo "token chargé (${#GH_TOKEN} caractères)"     # 40 caractères
   kubectl --context prod-01 -n wiki create secret docker-registry ghcr-pull \
     --docker-server=ghcr.io --docker-username=gaelbasta --docker-password="$GH_TOKEN"
   unset GH_TOKEN
   kubectl --context prod-01 -n wiki get secret ghcr-pull                  # kubernetes.io/dockerconfigjson   1
   ```
4. Premier déploiement : section B (image `2026.10.10-1638`, digest `sha256:f5768ebc…1316f4c`).

## B. Mettre le wiki à jour — ✅ 2026-10-10

```bash
cd ~/claude-projects/wiki
./scripts/construire.sh 2>&1 | tee build.log | grep -E '^==>|WARNING|ERROR|ERREUR|Error|Documentation built|^Image'
```
Attendu : `Documentation built`, aucun `WARNING` (un WARNING = lien cassé ou `.nav.yml` incorrect : corriger dans le repo concerné, push, recommencer), et la ligne `Image : ghcr.io/gaelbasta/wiki:<tag>`.

**Tester en local** (facultatif, conseillé si `mkdocs.yml` ou l'aspect a changé) :
```bash
docker run -d --rm --name wiki-test -p 8099:8080 ghcr.io/gaelbasta/wiki:<tag>
sleep 2; curl -sI http://localhost:8099/ | head -1                        # HTTP/1.1 200 OK
# navigateur : http://localhost:8099 (port relayé par VS Code), Ctrl+F5
docker stop wiki-test
```
Sans le `sleep 2`, le `curl` part avant que nginx écoute et ne répond rien.

**Publier puis déployer** (règle : fichier commité **avant** de déployer — ADR-021) :
```bash
docker push ghcr.io/gaelbasta/wiki:<tag>                                   # … digest: sha256:…
sed -i 's/tag: "[^"]*"/tag: "<tag>"/' deploy/values-prod.yaml
git diff                                                                   # une seule ligne : le tag
git commit -am "Wiki : déploiement prod de l'image <tag>" && git push
git status --short                                                         # vide
helm upgrade --install wiki oci://ghcr.io/gaelbasta/charts/plateforme --version 0.1.0 \
  -n wiki --create-namespace -f deploy/values-prod.yaml --kube-context prod-01 --wait --timeout 3m
```
Attendu : `STATUS: deployed`, révision +1.

## C. Vérifier — ✅ 2026-10-10

```bash
curl -sS https://wiki.prod.gba-lab.win | grep -o '<title>.*</title>'             # <title>Wiki PROD-01</title>
curl -sIL http://wiki.prod.gba-lab.win | grep -E '^(HTTP|Location)'              # 308 → https://… → 200
curl -sI https://wiki.prod.gba-lab.win/prod-01 | grep -iE '^(HTTP|Location)'     # 301, location: /prod-01/ (relative, sans :8080)
kubectl --context prod-01 -n wiki get pods                                       # 1/1 Running
helm history wiki -n wiki --kube-context prod-01
```
Puis navigateur du PC et du téléphone **en Wi-Fi** : cadenas valide, menu, recherche. (Constaté OK le 2026-10-10.)

## D. Revenir en arrière

| Situation | Commande |
|---|---|
| La nouvelle version du wiki pose problème | `helm rollback wiki -n wiki --kube-context prod-01 --wait`, puis remettre l'ancien tag dans `deploy/values-prod.yaml` (`git revert` du commit de déploiement) |
| Retirer le wiki | `helm uninstall wiki -n wiki --kube-context prod-01` (aucune donnée à perdre : tout est dans l'image et dans Git) |
| Tout supprimer | en plus : `kubectl --context prod-01 delete namespace wiki` (supprime aussi le secret `ghcr-pull`, à recréer : A.3) |
| Token `k3s-prod-01-pull` compromis | le révoquer sur GitHub, en créer un nouveau, puis dans **chaque** namespace qui a un `ghcr-pull` : `kubectl … delete secret ghcr-pull` et le recréer (A.3) |

## E. Ajouter un projet au wiki, régler le menu

1. Dans le repo **wiki**, ajouter une ligne à `projets.txt` : `<nom> git@github.com:gaelbasta/<repo>.git main md <Titre du menu>` (périmètre `md` en général ; `tout` seulement pour un repo sans données, si ses docs pointent vers des scripts ou YAML). Commit + push.
2. Facultatif, dans le repo du projet : un `.nav.yml` par dossier pour l'ordre. Modèle (celui de `docs/runbooks/` ici) :
   ```yaml
   nav:
     - README.md                  # page d'accueil du dossier en premier
     - premiere-page.md
     - Titre choisi: autre-page.md
     - Sous-dossier: sous-dossier
     - glob: "*"                  # tout le reste, par ordre alphabétique
       ignore_no_matches: true    # pas d'avertissement quand tout est déjà listé
   ```
   Sans `.nav.yml`, ordre alphabétique des **noms de fichiers** (le titre `#` est affiché). Syntaxe : https://lukasgeiter.github.io/mkdocs-awesome-nav/
3. Section B.

---

## Journal de mise au point (2026-10-10)

| Constat | Cause | Correction |
|---|---|---|
| Collecte en échec sur un repo sans `.md` | `git archive -- '*.md'` refuse un motif qui ne trouve rien | test préalable avec `git ls-files`, liste passée à `git archive` |
| Menu des runbooks en désordre | MkDocs trie par nom de fichier | plugin awesome-nav + fichiers `.nav.yml` dans prod-01 |
| `WARNING awesome-nav: The nav item '*' doesn't match…` | le joker final ne trouve rien quand toutes les pages sont listées | `glob: "*"` + `ignore_no_matches: true` |
| Premier `curl` local muet | lancé avant le démarrage de nginx | `sleep 2` avant le test |
| `Readiness probe failed … connection refused` au démarrage du pod | sonde passée une fraction de seconde avant que nginx écoute | aucune (le test suivant passe, pod `1/1`, 0 redémarrage) ; délai initial possible dans une future version du chart |
| Thème Material d'abord choisi | Gael préfère le rendu Read the Docs | thème `readthedocs` intégré à MkDocs (ADR-024) |
