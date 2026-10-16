# Chart plateforme

Chart Helm commun à tous les projets hébergés sur PROD-01 / PPROD (ADR-005, ADR-021, ADR-023).
Un projet n'écrit **aucun YAML Kubernetes** : seulement un `values-<env>.yaml` avec ce qui le concerne.

## Ce que le chart crée

| Objet | Rôle | Image |
|---|---|---|
| Deployment | lance le conteneur, le surveille (route de santé), le relance s'il tombe | le cuisinier |
| Service | adresse interne stable du conteneur | le numéro de la cuisine |
| Ingress | `host` → Service, en HTTPS (certificat wildcard par défaut, ADR-022) | le panneau à l'entrée |
| PersistentVolumeClaim | volume de données, si `persistence.enabled` (profil app) — **conservé après `helm uninstall`** | le casier |

## Les deux profils

| | `app` | `static` |
|---|---|---|
| Pour | API, backend, application avec serveur | wiki, landing page, front seul |
| Image | celle du projet | nginx **+ les fichiers du site**, construite par le projet (base conseillée : `nginxinc/nginx-unprivileged`) |
| Port par défaut | 8000 | 8080 |
| Santé par défaut | `/healthz` | `/` |
| Volume de données | possible (`persistence`) | non (les fichiers sont dans l'image) |

## Valeurs

| Valeur | Défaut | Obligatoire | Description |
|---|---|---|---|
| `profile` | `app` | | `app` ou `static` |
| `image.repository` | — | ✅ | ex. `ghcr.io/gaelbasta/prism` |
| `image.tag` | — | ✅ | version figée **entre guillemets** (`"1.10"`, sinon YAML lit 1.1), jamais `latest` |
| `image.pullPolicy` | `IfNotPresent` | | |
| `imagePullSecrets` | `[]` | | ex. `[ghcr-pull]` pour une image privée GHCR |
| `host` | — | ✅ | ex. `prism.prod.gba-lab.win` |
| `tls` | `true` | | HTTPS avec le certificat par défaut |
| `port` | 8000 / 8080 | | port écouté par le conteneur |
| `healthPath` | `/healthz` / `/` | | route de santé |
| `args` | `[]` | | arguments du conteneur |
| `replicas` | `1` | | forcé à 1 si `persistence` |
| `shutdownDelaySeconds` | `5` | | pause avant l'arrêt d'un ancien pod (déploiement sans coupure) ; max 25 |
| `env` | `{}` | | variables **non secrètes** |
| `secretEnv` | `[]` | | noms de Secrets (scellés dans `prod-01/secrets/`, ADR-032) injectés en variables |
| `accueil.enabled` | `false` | | **0.2.0** — l'app apparaît sur la page d'accueil https://home.prod.gba-lab.win (ADR-034) |
| `accueil.name` | nom de la release | | titre affiché |
| `accueil.group` | `Apps` | | rubrique de la page d'accueil |
| `accueil.icon` | — | | ex. `mdi-finance`, `si-wikidotjs` ([icônes](https://gethomepage.dev/configs/services/#icons)) |
| `accueil.description` | — | | une ligne sous le titre |
| `kubeContext` | `prod-01` | | **0.2.0** — contexte affiché dans les NOTES (mettre `k3d-dev-local` pour un test local) |
| `persistence.enabled` | `false` | | volume de données (profil app) |
| `persistence.size` | `1Gi` | | |
| `persistence.mountPath` | `/data` | | |
| `persistence.storageClass` | `""` | | vide = `local-path` (K3s) |
| `resources` | 50m / 64Mi, limite 256Mi | | |
| `podSecurityContext` | seccomp `RuntimeDefault` | | |

Une faute de frappe dans un nom de valeur (`hots:` au lieu de `host:`) est **refusée** par `values.schema.json`.
Les oublis graves (image, tag, host, `latest`) sont refusés avec un message en français.

## Exemple : `deploy/values-prod.yaml` d'un projet

```yaml
profile: app
image:
  repository: ghcr.io/gaelbasta/prism
  tag: "1.0.0"
imagePullSecrets: [ghcr-pull]
host: prism.prod.gba-lab.win
accueil:
  enabled: true
  icon: mdi-finance
  description: Observatoire financier
env:
  TZ: Europe/Paris
secretEnv: [prism-secrets]
persistence:
  enabled: true
  size: 5Gi
```

## Vérifier, publier

```bash
helm lint charts/plateforme -f <valeurs>                 # contrôle
helm template test charts/plateforme -f <valeurs>        # affiche le YAML produit, sans rien déployer
```
Publication sur GHCR : voir `docs/runbooks/deployer-une-app.md`. **Toute modification = nouvelle `version` dans `Chart.yaml`.**

## Historique des versions

| Version | Contenu |
|---|---|
| 0.1.0 (2026-10-10) | profils app/static, HTTPS par défaut, sondes, volume conservé, pause d'arrêt 5 s, schéma |
| 0.2.0 (2026-10-16) | bloc `accueil` (annotations Homepage sur l'Ingress, ADR-034) ; `enableServiceLinks: false` (plus de variables `<SERVICE>_PORT=tcp://…` injectées : piège PRISM_PORT du 2026-10-11) ; `kubeContext` dans les NOTES ; commentaires « secrets scellés » (ADR-032). **Compatible** : un fichier de valeurs 0.1.0 marche tel quel en 0.2.0. |

## Améliorations envisagées

- Délai initial pour la sonde de disponibilité (message `Readiness probe failed` sans effet juste après le démarrage du wiki).
