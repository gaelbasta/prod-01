# Standard d'hébergement PROD-01

> Statut : **ébauche** — sera complétée et testée en phase 5 (premier modèle) et phase 6 (wiki).
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
| Image | `ghcr.io/<compte>/<projet>:<version>` | `ghcr.io/<compte>/prism:1.0.0` |
| Version | jamais `latest` en prod | `1.0.0` |
| Données | toujours dans un volume, jamais dans l'image | — |
| Accès | LAN par défaut ; accès Tailscale ou public = ADR | — |

## Ce que chaque projet doit fournir

Dès le cadrage (étape ajoutée à `PROJECT_BOOTSTRAP.md`) :

1. **Profil d'hébergement** : static ou app.
2. **Données** : quoi, où, taille estimée, comment les sauvegarder (dump SQLite, etc.).
3. **Accès** : LAN seul / famille via Tailscale / public.
4. **Un dossier `docs/`** en Markdown, agrégé automatiquement dans le wiki.
5. **Une route de santé** (`/healthz` ou équivalent) pour les profils app, surveillée par Home Assistant.

## Déploiement : Helm (ADR-021)

Un **chart plateforme** commun (construit en phase 5) porte les profils `app` et `static`. Chaque projet fournit seulement ses fichiers de valeurs :

```
<projet>/deploy/
  values-prod.yaml     # PROD-01
  values-pprod.yaml    # PPROD (N100)
```

Déployer (depuis dev-linux ou le PC Windows) :
```bash
helm upgrade --install <projet> <chart-plateforme> \
  -n <projet> --create-namespace \
  -f deploy/values-prod.yaml --kube-context prod-01
```
Revenir en arrière : `helm rollback <projet> -n <projet> --kube-context prod-01`.

Règles : fichier de valeurs **commité** avant tout déploiement ; **aucun secret** dedans ; contexte **toujours explicite**.

## Parcours d'un projet

dev-linux (build & test) → image GHCR → PPROD (N100) → PROD (PROD-01)

> Tant que la PPROD n'existe pas (niveau 3), on passe directement de dev-linux à PROD-01.
