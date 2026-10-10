# Phase 5 (partie 1) — HTTPS : cert-manager et certificat wildcard

**Quoi** : obtenir automatiquement un certificat Let's Encrypt `*.prod.gba-lab.win` et le faire servir par défaut par Traefik, pour que toutes les apps soient en HTTPS valide sans configuration de leur côté.
**Réalisé le** : 2026-10-10 · **Durée** : ~35 min · **Depuis** : dev-linux (`~/claude-projects/prod-01`)
**Décision** : [ADR-022](../../DECISIONS.md) · **Fichiers** : [`platform/cert-manager/`](../../platform/cert-manager/), [`platform/traefik/`](../../platform/traefik/)

## Comment ça marche (version simple)

```
Bon de commande (Certificate)  ──►  cert-manager  ──►  Let's Encrypt : « prouve que gba-lab.win est à toi »
                                        │
                                        ├─► écrit un TXT _acme-challenge.prod chez Cloudflare (token API)
                                        │      Let's Encrypt le lit → OK → certificat délivré → TXT effacé
                                        ▼
                         coffre kube-system/wildcard-prod-tls  ──►  Traefik (TLSStore « default »)
                                                                       └─► toutes les apps *.prod.gba-lab.win
```

## Versions

| Élément | Version |
|---|---|
| cert-manager | v1.21.2 (chart OCI `oci://quay.io/jetstack/charts/cert-manager`) |
| Traefik (fourni par K3s) | 3.7.13 → objet `TLSStore` en `traefik.io/v1alpha1` |

> **Règle appliquée à chaque étape** : écrire le fichier → `git diff` → commit + push → **puis** appliquer au cluster (ADR-021).
> Toujours `--context prod-01` / `--kube-context prod-01` (sur dev-linux, le défaut est `k3d-dev-local`).

---

## 1. Token API Cloudflare

Tableau de bord Cloudflare → profil → **My Profile → API Tokens → Create Token** → modèle **Edit zone DNS** :

| Champ | Valeur |
|---|---|
| Token name | `cert-manager-prod-01` |
| Permissions | `Zone · DNS · Edit` **et** `Zone · Zone · Read` |
| Zone Resources | `Include · Specific zone · gba-lab.win` |
| Client IP Address Filtering | vide (IP publique non fixe) |
| TTL | pas de date de fin |

Le token (53 caractères) n'est affiché qu'**une fois** → gestionnaire de mots de passe. **Jamais dans Git.**

**Vérifier** (dev-linux, le token n'apparaît ni à l'écran ni dans l'historique) :
```bash
read -rs CF_TOKEN && echo "token chargé (${#CF_TOKEN} caractères)"
curl -s https://api.cloudflare.com/client/v4/user/tokens/verify \
  -H "Authorization: Bearer $CF_TOKEN" | grep -o '"status":"[a-z]*"'          # "status":"active"
curl -s "https://api.cloudflare.com/client/v4/zones?name=gba-lab.win" \
  -H "Authorization: Bearer $CF_TOKEN" | grep -o '"name":"gba-lab.win"'        # "name":"gba-lab.win"
unset CF_TOKEN
```

## 2. Installer cert-manager (Helm)

Valeurs : [`platform/cert-manager/values-prod.yaml`](../../platform/cert-manager/values-prod.yaml) — CRD installés et **conservés** à la désinstallation (`crds.keep`), vérification DNS sur `1.1.1.1`.

```bash
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.2 -n cert-manager --create-namespace \
  -f platform/cert-manager/values-prod.yaml --kube-context prod-01 --wait
```
Même commande pour une mise à jour (changer `--version` dans la commande **et** dans l'en-tête du fichier de valeurs).

**Vérifier** :
```bash
kubectl --context prod-01 -n cert-manager get pods          # 3 pods Running : cert-manager, cainjector, webhook
kubectl --context prod-01 get crd | grep cert-manager.io    # 6 CRD
helm list -n cert-manager --kube-context prod-01            # deployed, cert-manager-v1.21.2
```

## 3. Ranger le token dans un secret Kubernetes

Emplacement (ADR-008) : **`cert-manager/cloudflare-api-token`, clé `api-token`**.
```bash
read -rs CF_TOKEN && echo "token chargé (${#CF_TOKEN} caractères)"
printf '%s' "$CF_TOKEN" | kubectl --context prod-01 -n cert-manager \
  create secret generic cloudflare-api-token --from-file=api-token=/dev/stdin
unset CF_TOKEN
```
`printf … |` transmet le token par un tuyau : il n'apparaît pas sur la ligne de commande.

**Vérifier** (sans afficher la valeur) : `kubectl --context prod-01 -n cert-manager describe secret cloudflare-api-token` → `api-token: 53 bytes` (= nombre de caractères annoncé).

**Changer de token** (rotation, token révoqué) : créer le nouveau token dans Cloudflare, puis
`kubectl --context prod-01 -n cert-manager delete secret cloudflare-api-token` et refaire cette étape.

## 4. Guichets Let's Encrypt (ClusterIssuer)

Fichier : [`platform/cert-manager/cluster-issuers.yaml`](../../platform/cert-manager/cluster-issuers.yaml) — `letsencrypt-staging` puis `letsencrypt-prod`.
```bash
kubectl --context prod-01 apply -f platform/cert-manager/cluster-issuers.yaml
sleep 15
kubectl --context prod-01 get clusterissuer        # les deux à True
```
⚠️ Juste après l'`apply`, la colonne `READY` est **vide** (`AGE 0s`) : ce n'est pas une erreur, l'ouverture du compte Let's Encrypt prend quelques secondes. Vide ≠ `False`.

## 5. Certificat wildcard

Fichier : [`platform/cert-manager/wildcard-prod.yaml`](../../platform/cert-manager/wildcard-prod.yaml) — dans `kube-system` (là où Traefik lit son certificat par défaut).

**Toujours tester d'abord en staging** (quotas Let's Encrypt production : 5 échecs/heure, 50 certificats/semaine) : `issuerRef.name: letsencrypt-staging`, valider la chaîne jusqu'à l'étape 6, puis passer à `letsencrypt-prod` (une ligne) et réappliquer. cert-manager réémet automatiquement quand le guichet change.

```bash
kubectl --context prod-01 apply -f platform/cert-manager/wildcard-prod.yaml
kubectl --context prod-01 -n kube-system get certificate wildcard-prod -w     # attendre READY True, puis Ctrl+C
```
Le 2026-10-10 : **80 s** en staging, environ 1 min en production.

**Si READY reste False > 5 min** :
```bash
kubectl --context prod-01 get challenges -A
kubectl --context prod-01 -n kube-system describe certificate wildcard-prod | tail -15
```

## 6. Certificat par défaut de Traefik (TLSStore)

Fichier : [`platform/traefik/tlsstore-default.yaml`](../../platform/traefik/tlsstore-default.yaml) — nom `default` imposé, même namespace que le coffre. Pris en compte à chaud, sans coupure.
```bash
kubectl --context prod-01 apply -f platform/traefik/tlsstore-default.yaml
```

**Vérifier quel certificat est servi** :
```bash
echo | openssl s_client -connect 192.168.1.16:443 -servername test.prod.gba-lab.win 2>/dev/null \
  | openssl x509 -noout -subject -issuer -enddate
```

| Moment | `issuer` observé le 2026-10-10 |
|---|---|
| Avant TLSStore | `CN=TRAEFIK DEFAULT CERT` (faux certificat de Traefik) |
| Wildcard staging | `O=Let's Encrypt, CN=(STAGING) Ersatz Emmer YR2` |
| Wildcard production | `O=Let's Encrypt, CN=YR2` — `notAfter=Jan 8 2027` |

## 7. Test de bout en bout

Une app n'accepte le HTTPS que si son Ingress contient un bloc `tls:` (sans `secretName` → certificat par défaut). Le test de fumée [`tests/smoke-whoami.yaml`](../../tests/smoke-whoami.yaml) l'inclut.
```bash
kubectl --context prod-01 apply -f tests/smoke-whoami.yaml
curl -sS https://test.prod.gba-lab.win | head -3        # Hostname: whoami-… (curl vérifie le certificat)
```
Résultat du 2026-10-10 : ✅ cadenas valide sur le PC Windows, sur le téléphone (Wi-Fi) et dans `curl`.

---

## Revenir en arrière

| Situation | Solution |
|---|---|
| Mauvais certificat servi / problème Traefik | `kubectl --context prod-01 delete -f platform/traefik/tlsstore-default.yaml` → retour au faux certificat Traefik, sans coupure |
| Problème avec le certificat de production | remettre `letsencrypt-staging` dans `wildcard-prod.yaml` (`git revert`), réappliquer. **Ne pas relancer en boucle** en production (quotas) |
| Supprimer le certificat | `kubectl --context prod-01 delete -f platform/cert-manager/wildcard-prod.yaml` puis `kubectl --context prod-01 -n kube-system delete secret wildcard-prod-tls` |
| Désinstaller cert-manager | `helm uninstall cert-manager -n cert-manager --kube-context prod-01` puis `kubectl --context prod-01 delete namespace cert-manager`. Les CRD restent (`crds.keep`) ; réinstaller = même commande qu'à l'étape 2, Helm reprend les CRD sans erreur. **Testé en réel le 2026-10-10** (désinstallation par erreur, réinstallation OK en 2 min) |
| Token compromis | le révoquer dans Cloudflare (API Tokens → `…` → Delete), en créer un nouveau, refaire l'étape 3 |

## Reconstruire de zéro (PROD-01 réinstallé, ou PPROD)

1. Étape 2 (Helm) → 2. étape 3 (secret, token depuis le gestionnaire de mots de passe) → 3. `kubectl apply -f` de `cluster-issuers.yaml`, `wildcard-prod.yaml`, `tlsstore-default.yaml`.
Pour la PPROD : adapter le nom (`*.pprod.gba-lab.win`, `wildcard-pprod`) et utiliser un token dédié.
