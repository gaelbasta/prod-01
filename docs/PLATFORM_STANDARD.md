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

## Arborescence de déploiement (dans ce repo)

```
apps/
  <projet>/
    base/            # commun à tous les environnements
    overlays/
      pprod/         # différences PPROD (URL, données de test)
      prod/          # différences PROD
```

Déployer (niveau 1) : `kubectl apply -k apps/<projet>/overlays/prod`
Déployer (niveau 2) : commit + push, Argo CD s'en charge.

## Parcours d'un projet

dev-linux (build & test) → image GHCR → PPROD (N100) → PROD (PROD-01)

> Tant que la PPROD n'existe pas (niveau 3), on passe directement de dev-linux à PROD-01.
