# Secrets : Sealed Secrets (secrets chiffrés rangés dans Git)

**Quoi** : les secrets du cluster (tokens, mots de passe) sont rangés **chiffrés** dans ce repo, sous `secrets/prod-01/`. Seul PROD-01 sait les déchiffrer.
**Mis en service le** : 2026-10-15 (phase 10) · **Décisions** : [ADR-008](../../DECISIONS.md), [ADR-032](../../DECISIONS.md)
**Fichiers** : [`platform/sealed-secrets/values-prod.yaml`](../../platform/sealed-secrets/values-prod.yaml) · [`platform/sealed-secrets/prod-01-cert.pem`](../../platform/sealed-secrets/prod-01-cert.pem) · [`secrets/prod-01/`](../../secrets/prod-01/)

---

## En deux minutes (à relire quand on a tout oublié)

**L'image** : une boîte aux lettres à cadenas.

- **Le cadenas ouvert = le certificat public** (`platform/sealed-secrets/prod-01-cert.pem`). Tout le monde peut l'avoir. Avec lui, on **ferme** une enveloppe, mais on ne peut pas l'ouvrir.
- **La clé du cadenas = la clé privée**. Elle vit **dans PROD-01** (secret `kube-system/sealed-secrets-key72g5d`). Une copie est rangée dans le **gestionnaire de mots de passe** (« Sealed Secrets – clé prod-01 »).
- **Le facteur = le contrôleur** (`sealed-secrets-controller`, dans `kube-system`). Il prend chaque enveloppe posée dans le cluster (un objet `SealedSecret`), l'ouvre avec la clé, et en sort un **Secret** Kubernetes normal, celui que les apps utilisent.

**Le trajet d'un secret** :
```
dev-linux                                   Git (repo prod-01)            PROD-01
token tapé (read -rs) ──► kubeseal ──► secrets/prod-01/<ns>/<nom>.yaml ──► kubectl apply ──► contrôleur
                         (cadenas public)  (enveloppe chiffrée,           (SealedSecret)      ouvre l'enveloppe
                                           commitable sans risque)                            ──► Secret <ns>/<nom>
```

**Les 4 choses à retenir** :
1. **Une enveloppe est liée à son namespace et à son nom.** Celle de `prism/ghcr-pull` ne peut pas servir pour `wiki/ghcr-pull` (même si le contenu est identique) : on en fabrique une par namespace.
2. **Changer un secret = refaire l'enveloppe**, puis commit, puis `kubectl apply`. On ne modifie plus jamais un secret à la main.
3. **Supprimer un `SealedSecret` supprime aussi le Secret qu'il a produit.** ⚠️ Ne jamais faire `kubectl delete sealedsecret` sur une app en service sans savoir pourquoi.
4. **Si la clé privée est perdue** (PROD-01 détruit), les enveloppes de Git deviennent illisibles… **sauf** grâce à la copie du gestionnaire de mots de passe (procédure E, **testée le 2026-10-15**).

**Inventaire (2026-10-15)** — tous `SYNCED True` :

| Secret (namespace/nom) | Fichier | Contenu | Valeur d'origine (gestionnaire) | Empreinte de contrôle* |
|---|---|---|---|---|
| `cert-manager/cloudflare-api-token` | `secrets/prod-01/cert-manager/cloudflare-api-token.yaml` | clé `api-token` | token Cloudflare `cert-manager-prod-01` (53 car.) | `dc2d3691…15a48` |
| `wiki/ghcr-pull` | `secrets/prod-01/wiki/ghcr-pull.yaml` | `.dockerconfigjson` (type `kubernetes.io/dockerconfigjson`) | token GitHub `k3s-prod-01-pull` (40 car.) | `e0796215…a00bb5` |
| `prism/ghcr-pull` | `secrets/prod-01/prism/ghcr-pull.yaml` | idem | idem | `e0796215…a00bb5` |
| `prism/prism-secrets` | `secrets/prod-01/prism/prism-secrets.yaml` | clé `PRISM_MOT_DE_PASSE` | mot de passe PRISM | `f8f8ff39…f6313a` |

\* `sha256sum` de la valeur encodée telle que le cluster la stocke (commandes en C) : permet de vérifier qu'un contenu n'a pas changé **sans jamais l'afficher**.

**Où est quoi** :

| Élément | Où |
|---|---|
| Clé privée | PROD-01 : secret `kube-system/sealed-secrets-key72g5d` (donc dans la base K3s → sauvegarde restic chaque nuit) · gestionnaire : « Sealed Secrets – clé prod-01 » (pièce jointe `sealed-secrets-key-prod-01.yaml`, sha256 `938cd832…aac68f7a`) |
| Certificat public | `platform/sealed-secrets/prod-01-cert.pem` — valable jusqu'au **12/10/2036** — empreinte `62:5A:51:6A:…:F3:48:E7` |
| Outil `kubeseal` | dev-linux uniquement (`/usr/local/bin/kubeseal`, 0.40.0). **Pas installé sur le PC Windows.** |
| Catalogue Helm | `sealed-secrets` → `https://bitnami.github.io/sealed-secrets` (déclaré sur dev-linux) |

---

## A. Mise en place (faite une fois) — ✅ 2026-10-15

> ⚠️ Toutes les commandes : sur **dev-linux** (`gael@dev-linux`), dans `~/claude-projects/prod-01`. Contexte PROD-01 **toujours explicite**.

### A1. Installer `kubeseal` sur dev-linux

```bash
V=0.40.0
D=$(mktemp -d) && cd "$D"
curl -fsSLO "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${V}/kubeseal-${V}-linux-amd64.tar.gz"
curl -fsSLO "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${V}/sealed-secrets_${V}_checksums.txt"
sha256sum --check --ignore-missing "sealed-secrets_${V}_checksums.txt"     # → kubeseal-0.40.0-linux-amd64.tar.gz: OK
tar -xzf "kubeseal-${V}-linux-amd64.tar.gz" kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
kubeseal --version                                                         # kubeseal version: 0.40.0
cd ~ && rm -rf "$D"
```
Le projet a déménagé de `bitnami-labs` vers `bitnami` sur GitHub : les téléchargements sont redirigés, ça marche avec l'une ou l'autre adresse.

### A2. Déclarer le catalogue Helm

```bash
helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
helm repo update sealed-secrets
helm search repo sealed-secrets/sealed-secrets --versions | head -4         # 2.20.0   0.40.0
```
**Piège rencontré** : l'ancienne adresse `https://bitnami-labs.github.io/sealed-secrets` répond **404** (GitHub Pages ne suit pas le déménagement). Utiliser `bitnami.github.io`.

### A3. Installer le contrôleur

Valeurs : [`platform/sealed-secrets/values-prod.yaml`](../../platform/sealed-secrets/values-prod.yaml) — nom `sealed-secrets-controller` (celui que `kubeseal` cherche par défaut), **renouvellement de clé désactivé** (`keyrenewperiod: "0"`, ADR-032), petites limites de ressources. Commité **avant** l'installation.

```bash
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --version 2.20.0 -n kube-system \
  -f platform/sealed-secrets/values-prod.yaml --kube-context prod-01 --wait
```

**Vérifier** :
```bash
helm list -n kube-system --kube-context prod-01 | grep sealed               # deployed  sealed-secrets-2.20.0  0.40.0
kubectl --context prod-01 -n kube-system get pods -l app.kubernetes.io/name=sealed-secrets   # 1/1 Running
kubectl --context prod-01 -n kube-system get deploy sealed-secrets-controller \
  -o jsonpath='{.spec.template.spec.containers[0].args}{"\n"}'               # contient "--key-renew-period","0"
kubectl --context prod-01 -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key   # UNE clé
kubeseal --context prod-01 --fetch-cert | head -1                           # -----BEGIN CERTIFICATE-----
```
Constaté : une clé `sealed-secrets-key72g5d` (type `kubernetes.io/tls`), journal `New key written`, certificat valable 10 ans.

### A4. Ranger le certificat public dans Git

```bash
kubeseal --context prod-01 --fetch-cert > platform/sealed-secrets/prod-01-cert.pem
openssl x509 -in platform/sealed-secrets/prod-01-cert.pem -noout -enddate -fingerprint -sha256
git add platform/sealed-secrets/prod-01-cert.pem && git commit -m "…" && git push
```
Ce n'est **pas** un secret. Il permet de sceller **sans accès au cluster** (`kubeseal --cert …`).

### A5. Sauvegarder la clé privée dans le gestionnaire de mots de passe

```bash
( umask 077
  kubectl --context prod-01 -n kube-system get secret \
    -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > ~/sealed-secrets-key-prod-01.yaml )
ls -l ~/sealed-secrets-key-prod-01.yaml                  # -rw-------  (lisible par moi seul)
grep -c 'tls.key:' ~/sealed-secrets-key-prod-01.yaml     # 1
sha256sum ~/sealed-secrets-key-prod-01.yaml              # noter l'empreinte dans l'entrée du gestionnaire
```
Fichier écrit **hors du repo** (dossier personnel), **jamais** affiché (`cat` interdit). Entrée créée : **« Sealed Secrets – clé prod-01 »**, avec le fichier en pièce jointe, le nom de la clé, l'empreinte du fichier, l'empreinte du certificat et la date. Le fichier local n'est effacé (`shred -u`) qu'**après** le test de restauration (E).

### A6. Test de restauration de la clé — ✅ 2026-10-15

Procédure E jouée sur `k3d-dev-local`, avec la copie **téléchargée depuis le gestionnaire** (empreinte identique) : un secret d'essai scellé avec le certificat de Git a été ouvert (`bonjour-phase-10`). Puis nettoyage complet de k3d et `shred -u` des fichiers de clé. La clé n'existe plus qu'à deux endroits : PROD-01 (+ restic) et le gestionnaire.

### A7. Migration des 4 secrets créés à la main — ✅ 2026-10-15, sans coupure

Pour chacun, dans l'ordre wiki → `prism/ghcr-pull` → `prism-secrets` → Cloudflare : procédure D. Les 4 empreintes « après » sont identiques aux « avant » ; aucun pod n'a redémarré ; certificat wildcard et guichets Let's Encrypt toujours `True`.

---

## B. Créer un secret pour une **nouvelle** app

> Exemple : namespace `monapp`, secret `monapp-secrets`, une clé `MON_TOKEN`. Valeur rangée **d'abord** dans le gestionnaire de mots de passe.

```bash
cd ~/claude-projects/prod-01
mkdir -p secrets/prod-01/monapp
read -rs VALEUR && echo "valeur chargée (${#VALEUR} caractères)"
printf '%s' "$VALEUR" | kubectl create secret generic monapp-secrets -n monapp \
  --from-file=MON_TOKEN=/dev/stdin --dry-run=client -o yaml \
| kubeseal --cert platform/sealed-secrets/prod-01-cert.pem --format yaml > secrets/prod-01/monapp/monapp-secrets.yaml
unset VALEUR
grep -E '^  name:|^  namespace:' secrets/prod-01/monapp/monapp-secrets.yaml     # bon nom, bon namespace
git add secrets/prod-01/monapp/ && git commit -m "monapp : SealedSecret monapp-secrets" && git push
kubectl --context prod-01 create namespace monapp           # si le namespace n'existe pas encore
kubectl --context prod-01 apply -f secrets/prod-01/monapp/monapp-secrets.yaml
kubectl --context prod-01 -n monapp get sealedsecret         # SYNCED True
```
- **Accès à une image privée GHCR** (`ghcr-pull`) : même chose, avec `kubectl create secret docker-registry ghcr-pull -n monapp --docker-server=ghcr.io --docker-username=gaelbasta --docker-password="$GH_TOKEN" --dry-run=client -o yaml | kubeseal …` (token `k3s-prod-01-pull`).
- **Plusieurs clés dans un même secret** (non pratiqué) : un `read -rs` par valeur, puis une option `--from-file` par clé, chacune alimentée par `<(printf '%s' "$X")` au lieu de `/dev/stdin` :
  `kubectl create secret generic monapp-secrets -n monapp --from-file=CLE_A=<(printf '%s' "$A") --from-file=CLE_B=<(printf '%s' "$B") --dry-run=client -o yaml | kubeseal …`. Jamais `--from-literal` (la valeur apparaîtrait dans l'historique du terminal).
- Puis le `helm upgrade --install` habituel ([deployer-une-app.md](deployer-une-app.md)) : `secretEnv: [monapp-secrets]`, `imagePullSecrets: [ghcr-pull]`.

**Statut** : geste pratiqué sur k3d (A6) ; première vraie app à venir.

## C. Changer la valeur d'un secret (rotation, token révoqué, nouveau mot de passe)

> ⚠️ **Pas encore pratiqué en réel** (2026-10-15). Compléter cette section la première fois.

1. Mettre la **nouvelle** valeur dans le gestionnaire (et, pour un token, le créer chez GitHub / Cloudflare).
2. Refaire l'enveloppe **avec le même nom de fichier** (commandes de B, ou celles de D2 pour les 4 secrets existants) : le fichier est écrasé.
3. `git diff --stat` (le fichier change entièrement : normal, le chiffrement est différent à chaque fois), commit, push.
4. `kubectl --context prod-01 apply -f secrets/prod-01/<ns>/<nom>.yaml` → le contrôleur réécrit le Secret (pas besoin d'annotation : il en est déjà propriétaire).
5. Vérifier : `SYNCED True`, et l'empreinte (commande C de D1) **a changé**.
6. **Faire relire la nouvelle valeur par l'app** :

| Secret | Quand la nouvelle valeur est-elle utilisée ? |
|---|---|
| `prism-secrets` (variable d'environnement) | **seulement au redémarrage du pod** : `kubectl --context prod-01 -n prism rollout restart deploy/prism` |
| `ghcr-pull` | au prochain téléchargement d'image (nouvelle version) ; rien à faire |
| `cloudflare-api-token` | au prochain renouvellement du certificat ; rien à faire |

**Token `k3s-prod-01-pull` changé** : refaire **une enveloppe par namespace** (`wiki`, `prism`, et toute nouvelle app).

## D. Faire passer sous Sealed Secrets un secret créé à la main — ✅ 2026-10-15 (×4)

La méthode « **empreinte avant = empreinte après** » : on ne remplace un secret en service que si l'on a **prouvé** que la valeur du gestionnaire est la même.

### D1. Empreinte « avant » (sans afficher la valeur)

```bash
kubectl --context prod-01 -n prism get secret prism-secrets -o jsonpath='{.data.PRISM_MOT_DE_PASSE}' | sha256sum
# pour un ghcr-pull :  -o jsonpath='{.data.\.dockerconfigjson}'
# pour Cloudflare   :  -n cert-manager get secret cloudflare-api-token -o jsonpath='{.data.api-token}'
```
Pour voir les **noms** des clés d'un secret (jamais les valeurs) :
```bash
kubectl --context prod-01 -n prism get secret prism-secrets -o go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}'
```

### D2. Même empreinte avec la valeur du gestionnaire, puis enveloppe

```bash
read -rs MDP && echo "chargé (${#MDP} caractères)"
printf '%s' "$MDP" | kubectl create secret generic prism-secrets -n prism \
  --from-file=PRISM_MOT_DE_PASSE=/dev/stdin --dry-run=client -o jsonpath='{.data.PRISM_MOT_DE_PASSE}' | sha256sum
#   ↑ DOIT être identique à D1. Sinon : STOP, ne rien appliquer.
printf '%s' "$MDP" | kubectl create secret generic prism-secrets -n prism \
  --from-file=PRISM_MOT_DE_PASSE=/dev/stdin --dry-run=client -o yaml \
| kubeseal --cert platform/sealed-secrets/prod-01-cert.pem --format yaml > secrets/prod-01/prism/prism-secrets.yaml
unset MDP
```
- `printf '%s'` (et non `echo`) : **pas de retour à la ligne** ajouté — c'est ainsi que les secrets d'origine ont été créés.
- `ghcr-pull` : `kubectl create secret docker-registry ghcr-pull -n <ns> --docker-server=ghcr.io --docker-username=gaelbasta --docker-password="$GH_TOKEN" --dry-run=client …`
- Cloudflare : `printf '%s' "$CF_TOKEN" | kubectl create secret generic cloudflare-api-token -n cert-manager --from-file=api-token=/dev/stdin --dry-run=client …`

Puis : `git add`, `git commit`, `git push`.

### D3. Passage sous Sealed Secrets

```bash
kubectl --context prod-01 -n prism annotate secret prism-secrets sealedsecrets.bitnami.com/managed=true
kubectl --context prod-01 apply -f secrets/prod-01/prism/prism-secrets.yaml
sleep 5
kubectl --context prod-01 -n prism get sealedsecret prism-secrets                         # SYNCED True
# empreinte « après » = commande D1 → identique
kubectl --context prod-01 -n prism get secret prism-secrets -o jsonpath='{.metadata.ownerReferences[0].kind}{"\n"}'   # SealedSecret
```
L'annotation `managed=true` autorise le contrôleur à **prendre en charge** un secret qu'il n'a pas créé ; sans elle, il refuse d'y toucher (protection).

**Revenir en arrière** :

| Situation | Que faire |
|---|---|
| `SYNCED False` | le secret d'origine n'a pas été touché : `kubectl --context prod-01 -n <ns> delete sealedsecret <nom>` |
| Empreinte « après » différente | ne **pas** redémarrer l'app ; `delete sealedsecret <nom>` (qui supprime le Secret), puis recréer le secret à la main depuis le gestionnaire (ancienne méthode : `printf '%s' "$X" \| kubectl --context prod-01 -n <ns> create secret generic <nom> --from-file=<CLE>=/dev/stdin`) |

## E. Restaurer la clé privée (PROD-01 reconstruit, ou test) — ✅ testé sur k3d le 2026-10-15

> Ordre impératif : **la clé d'abord, le contrôleur ensuite**. Sinon le contrôleur fabrique une nouvelle clé au démarrage (journal `New key written`) et les enveloppes de Git restent illisibles.

1. Télécharger la pièce jointe de « Sealed Secrets – clé prod-01 » sous `~/cle-restauree.yaml`, puis :
   ```bash
   chmod 600 ~/cle-restauree.yaml
   sha256sum ~/cle-restauree.yaml          # = l'empreinte notée dans le gestionnaire (938cd832…aac68f7a)
   ```
2. Poser la clé dans le cluster (ici `prod-01` ; pour le test : `k3d-dev-local`) :
   ```bash
   grep -vE '^\s+(resourceVersion|uid|creationTimestamp):' ~/cle-restauree.yaml \
     | kubectl --context prod-01 apply -f -                 # secret/sealed-secrets-key72g5d created
   ```
   Le `grep -v` retire 3 lignes d'identité propres à l'ancien cluster, qu'un nouveau cluster refuserait. La clé elle-même n'est pas modifiée.
3. Installer le contrôleur (A3). **Vérifier** : le journal dit `registered private key … sealed-secrets-key72g5d` et **pas** `New key written` :
   ```bash
   kubectl --context prod-01 -n kube-system logs deploy/sealed-secrets-controller | head -8
   ```
4. Créer les namespaces, puis reposer toutes les enveloppes :
   ```bash
   for ns in cert-manager wiki prism; do kubectl --context prod-01 create namespace "$ns"; done   # (« already exists » = sans gravité)
   kubectl --context prod-01 apply -R -f secrets/prod-01/
   kubectl --context prod-01 get sealedsecret -A          # tous SYNCED True
   ```
5. Effacer la copie locale : `shred -u ~/cle-restauree.yaml`.

**Si la copie du gestionnaire est perdue aussi** : la clé est dans la base K3s, sauvegardée chaque nuit (restaurer `state.db` : [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md)). En dernier recours : nouvelle clé, puis **refaire toutes les enveloppes** (procédure B pour chaque secret, valeurs depuis le gestionnaire) et ranger le nouveau certificat dans Git.

## F. Mettre à jour le contrôleur

```bash
helm repo update sealed-secrets
helm search repo sealed-secrets/sealed-secrets --versions | head -4
# lire les notes de version (github.com/bitnami/sealed-secrets/releases), puis changer --version
# dans l'en-tête de values-prod.yaml ET dans la commande ; commit ; puis :
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets --version <nouvelle> -n kube-system \
  -f platform/sealed-secrets/values-prod.yaml --kube-context prod-01 --wait
kubectl --context prod-01 get sealedsecret -A                 # toujours SYNCED True
```
Revenir en arrière : `helm rollback sealed-secrets -n kube-system --kube-context prod-01`. La clé et les enveloppes ne sont pas touchées par une mise à jour. Mettre aussi `kubeseal` à la même version (A1).

## G. Désinstaller (à ne faire que pour une bonne raison)

| Geste | Effet |
|---|---|
| `helm uninstall sealed-secrets -n kube-system --kube-context prod-01` | le contrôleur disparaît ; **les Secrets déjà produits restent** et les apps continuent ; la clé et le type `SealedSecret` (CRD) restent aussi |
| `kubectl --context prod-01 delete crd sealedsecrets.bitnami.com` | ⚠️ supprime **tous** les `SealedSecret` **et donc tous les Secrets qu'ils ont produits** → apps cassées au prochain redémarrage. Ne jamais faire sur PROD-01 sans avoir recréé les secrets à la main |

## Pièges et bonnes pratiques

- **Toujours** `read -rs` + `printf '%s' … | … --from-file=CLE=/dev/stdin` : la valeur ne passe ni dans l'historique du terminal, ni dans un fichier. Puis `unset`.
- **Jamais** de fichier de secret **en clair** dans le repo ; seuls les fichiers produits par `kubeseal` (champ `encryptedData`, valeurs `AgB…`) y vont.
- **Contrôle avant commit** : `grep -E '^  name:|^  namespace:' <fichier>` — un mauvais namespace = enveloppe inutilisable (`SYNCED False`).
- `kubectl get secret … -o yaml` **affiche** les valeurs (encodées en base64, donc lisibles) : préférer `describe` (tailles seulement) ou les empreintes `sha256sum`.
- Le certificat public expire le **12/10/2036** (renouvellement désactivé, ADR-032) : à revoir avant.
