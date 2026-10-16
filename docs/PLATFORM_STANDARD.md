# Standard d'hébergement PROD-01

> Statut : **en service** depuis la phase 5 (chart plateforme 0.1.0, 2026-10-10 ; **0.2.0** depuis le 2026-10-17, ADR-034). Premier vrai projet : wiki (phase 6, profil static, image privée).
> Référencé par la **méthode Claude** (repo `claude-method`, V1.2) : `/cadrer` lit ce fichier dès qu'un projet doit être hébergé.
>
> **Pour Claude Code travaillant sur un autre projet** : ce repo est en **lecture seule**. Ce qui doit y être ajouté pour le projet (secret scellé, adresse surveillée, appel de sauvegarde — et, dans le repo `wiki`, la ligne de `projets.txt`) est listé pour Gael en ACTION MANUELLE ; aucun `kubectl` / `helm` vers PROD-01 sans sa demande explicite.

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
| Repo | GitHub **privé** `gaelbasta/<projet>` (nécessaire pour l'image GHCR et le wiki) | `gaelbasta/prism` |
| Image | `ghcr.io/gaelbasta/<projet>:<version>` | `ghcr.io/gaelbasta/prism:1.0.0` |
| Version | jamais `latest` en prod | `1.0.0` |
| Données | toujours dans un volume, jamais dans l'image | — |
| Accès | LAN + mes appareils via Tailscale, automatiquement pour toute app (ADR-033) ; famille via Tailscale = règles d'accès à écrire ; public = ADR | — |
| HTTPS | automatique : certificat wildcard servi par défaut (ADR-022), **aucun certificat à gérer par projet** | — |

## Ce que chaque projet doit fournir

Dès le cadrage (`/cadrer` de la méthode Claude) :

1. **Profil d'hébergement** : static ou app.
2. **Données** : quoi, où, taille estimée, comment les sauvegarder (dump SQLite, etc.).
3. **Accès** : LAN seul / famille via Tailscale / public.
4. **Un dossier `docs/`** en Markdown, publié dans le wiki (une ligne dans `projets.txt` du repo wiki ; ordre du menu via des fichiers `.nav.yml` facultatifs — runbook [wiki.md](runbooks/wiki.md), ADR-024).
5. **Une route de santé** (`/healthz` ou équivalent) pour les profils app, **surveillée depuis `pprod-01`** : ajouter son adresse à `urls` dans `monitoring/telegraf/pprod-01.conf` puis rejouer `telegraf.sh` sur `pprod-01` — l'alerte « App de PROD-01 injoignable » la prend en compte toute seule ([runbook surveillance](runbooks/surveillance.md), section D ; ADR-031).
6. **Si l'app a des données** : une commande de **copie cohérente** (comme `sauvegarder.ts` de PRISM, contrat ADR-027) et son appel ajouté à l'étape 1 de `scripts/sauvegarde-prod-01.sh` ; les bases vivantes exclues de restic ([runbook sauvegarde](runbooks/sauvegarde-et-restauration.md)).

7. **Ses secrets** (tokens, mots de passe, accès à l'image privée `ghcr-pull`) : la **liste** (nom du secret, clés), jamais les valeurs. Ils sont scellés dans **ce** repo, `secrets/prod-01/<projet>/` (ADR-032, [runbook secrets](runbooks/secrets.md), B) ; le projet ne fait que les nommer dans `values-prod.yaml` (`secretEnv`, `imagePullSecrets`).

8. **Sa tuile sur la page d'accueil** : bloc `accueil` (nom, icône, description) dans `values-prod.yaml` — l'app apparaît sur https://home.prod.gba-lab.win dès son déploiement ([runbook accueil](runbooks/accueil.md), B ; ADR-034).

## Déploiement : Helm (ADR-021, ADR-023)

Le **chart plateforme** (`oci://ghcr.io/gaelbasta/charts/plateforme`, source `charts/plateforme/`) porte les profils `app` et `static`. Chaque projet fournit seulement ses fichiers de valeurs :

```
<projet>/deploy/
  values-prod.yaml     # PROD-01
  values-pprod.yaml    # PPROD (N100)
```

Déployer (depuis dev-linux ou le PC Windows, après `helm registry login ghcr.io`) :
```bash
helm upgrade --install <projet> oci://ghcr.io/gaelbasta/charts/plateforme --version 0.2.0 \
  -n <projet> --create-namespace -f deploy/values-prod.yaml --kube-context prod-01 --wait
```
Revenir en arrière : `helm rollback <projet> -n <projet> --kube-context prod-01`.

Règles : fichier de valeurs **commité** avant tout déploiement ; **aucun secret** dedans (il ne fait que nommer les secrets, eux-mêmes scellés dans `prod-01/secrets/prod-01/<projet>/` — ADR-032, [runbook secrets](runbooks/secrets.md)) ; contexte **toujours explicite** ; version du chart **toujours explicite**.
Procédure complète : [runbooks/deployer-une-app.md](runbooks/deployer-une-app.md). Valeurs disponibles : [README du chart](../charts/plateforme/README.md).

Fourni automatiquement par la plateforme : HTTPS valide, redirection `http://` → `https://`, mises à jour sans coupure, relance si l'app plante, volume de données conservé après désinstallation.

## Parcours d'un projet

dev-linux (build & test) → image GHCR → PPROD (N100) → PROD (PROD-01)

> Tant que la PPROD n'existe pas (niveau 3), on passe directement de dev-linux à PROD-01.
