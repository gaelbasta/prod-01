# Standard d'hébergement PROD-01

> Statut : **en service** depuis la phase 5 (chart plateforme 0.1.0, 2026-10-10). Premier vrai projet : wiki (phase 6, profil static, image privée).
> Référencé par `METHOD.md` et `PROJECT_BOOTSTRAP.md`.

## Règle d'or

**Tout projet hébergé l'est sur K3s, selon l'un des deux profils ci-dessous.** Rien d'autre (pas de Docker Compose, pas de service lancé à la main sur l'hôte).

## Les deux profils

| Profil | Pour quoi | Contenu |
|---|---|---|
| **static** | Site sans serveur : wiki, landing page, front seul, doc | nginx qui sert des fichiers |
| **app** | Application avec un serveur (API, backend) | 1 conteneur + volume de données (SQLite) ; PostgreSQL seulement si justifié |

## Conventions

| Élément | Règle | Exemple |
|---|---|---|
| Nom du projet | minuscules, tirets | `prism` |
| Namespace | = nom du projet | `prism` |
| URL prod | `<projet>.prod.gba-lab.win` | `prism.prod.gba-lab.win` |
| URL pprod | `<projet>.pprod.gba-lab.win` | `prism.pprod.gba-lab.win` |
| Image | `ghcr.io/gaelbasta/<projet>:<version>` | `ghcr.io/gaelbasta/prism:1.0.0` |
| Version | jamais `latest` en prod | `1.0.0` |
| Données | toujours dans un volume, jamais dans l'image | — |
| Accès | LAN par défaut ; accès Tailscale ou public = ADR | — |
| HTTPS | automatique : certificat wildcard servi par défaut (ADR-022), **aucun certificat à gérer par projet** | — |

## Ce que chaque projet doit fournir

Dès le cadrage (étape ajoutée à `PROJECT_BOOTSTRAP.md`) :

1. **Profil d'hébergement** : static ou app.
2. **Données** : quoi, où, taille estimée, comment les sauvegarder (dump SQLite, etc.).
3. **Accès** : LAN seul / famille via Tailscale / public.
4. **Un dossier `docs/`** en Markdown, publié dans le wiki (une ligne dans `projets.txt` du repo wiki ; ordre du menu via des fichiers `.nav.yml` facultatifs — runbook [wiki.md](runbooks/wiki.md), ADR-024).
5. **Une route de santé** (`/healthz` ou équivalent) pour les profils app, surveillée par Home Assistant.

## Déploiement : Helm (ADR-021, ADR-023)

Le **chart plateforme** (`oci://ghcr.io/gaelbasta/charts/plateforme`, source `charts/plateforme/`) porte les profils `app` et `static`. Chaque projet fournit seulement ses fichiers de valeurs :

```
<projet>/deploy/
  values-prod.yaml     # PROD-01
  values-pprod.yaml    # PPROD (N100)
```

Déployer (depuis dev-linux ou le PC Windows, après `helm registry login ghcr.io`) :
```bash
helm upgrade --install <projet> oci://ghcr.io/gaelbasta/charts/plateforme --version 0.1.0 \
  -n <projet> --create-namespace -f deploy/values-prod.yaml --kube-context prod-01 --wait
```
Revenir en arrière : `helm rollback <projet> -n <projet> --kube-context prod-01`.

Règles : fichier de valeurs **commité** avant tout déploiement ; **aucun secret** dedans ; contexte **toujours explicite** ; version du chart **toujours explicite**.
Procédure complète : [runbooks/deployer-une-app.md](runbooks/deployer-une-app.md). Valeurs disponibles : [README du chart](../charts/plateforme/README.md).

Fourni automatiquement par la plateforme : HTTPS valide, redirection `http://` → `https://`, mises à jour sans coupure, relance si l'app plante, volume de données conservé après désinstallation.

## Parcours d'un projet

dev-linux (build & test) → image GHCR → PPROD (N100) → PROD (PROD-01)

> Tant que la PPROD n'existe pas (niveau 3), on passe directement de dev-linux à PROD-01.
