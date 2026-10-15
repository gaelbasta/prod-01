# PROD-01 — Serveur de production principal

> **Tu es perdu ? Commence ici.** Ce fichier est le point d'entrée unique.
> Tout ce qui concerne PROD-01 est dans ce repo : décisions, procédures, configuration.
>
> Repo : https://github.com/gaelbasta/prod-01 (privé) — copie de travail : `~/claude-projects/prod-01` sur dev-linux.

## En une phrase

PROD-01 est un mini-PC GMKtec K8 Plus sous Ubuntu Server. Il fait tourner un Kubernetes léger (K3s) qui héberge mes projets (PRISM en premier), accessibles en HTTPS sur le LAN, et plus tard depuis l'extérieur via Tailscale.

## Où trouver quoi

| Je veux… | Aller dans |
|---|---|
| Comprendre comment tout s'articule (version simple) | [docs/architecture/vue-ensemble.md](docs/architecture/vue-ensemble.md) |
| Savoir où on en est / ce qui reste à faire | [ROADMAP.md](ROADMAP.md) |
| Savoir **pourquoi** on a fait tel choix | [DECISIONS.md](DECISIONS.md) |
| Comprendre un mot technique | [docs/GLOSSAIRE.md](docs/GLOSSAIRE.md) |
| Héberger un nouveau projet | [docs/PLATFORM_STANDARD.md](docs/PLATFORM_STANDARD.md) |
| Faire une opération (se connecter, redémarrer, restaurer…) | [docs/runbooks/](docs/runbooks/) |
| Reprendre le chantier avec Claude dans une nouvelle conversation | [docs/REPRISE.md](docs/REPRISE.md) |
| Lire toute cette doc dans un navigateur | **https://wiki.prod.gba-lab.win** (LAN) — mise à jour : [runbook wiki](docs/runbooks/wiki.md) |

## Règles du repo

1. **Une décision = une entrée dans `DECISIONS.md`**, avec le pourquoi. Pas de décision orale.
2. **Une opération faite deux fois = un runbook.** Le runbook est écrit à partir de ce qui a *réellement* été fait, pas de la théorie.
3. **Aucun secret dans ce repo** (mots de passe, tokens, clés privées). Seulement l'endroit où ils sont rangés.
4. Chaque runbook répond à 4 questions : *quoi*, *comment* (commandes exactes), *comment vérifier*, *comment revenir en arrière*.

## Machines

| Nom | Matériel | Rôle | État |
|---|---|---|---|
| PROD-01 | GMKtec K8 Plus — Ryzen 7 8845HS, 32 Go, NVMe 1 To | Production | K3s + HTTPS en service |
| `pprod-01` (N100, ex-`gbaubu02p`) | Mini-PC Intel N100, SSD 512 Go | Cible de sauvegarde (ADR-027), puis PPROD (phase 14) | Ubuntu Server 26.04.1 + socle (2026-10-10) ; coffre de sauvegarde en service : disque IronWolf 4 To, rest-server append-only (2026-10-14) |
| dev-linux | Workstation Ubuntu | Développement et build | En service |
| Home Assistant | — | Surveillance et alertes | En service |
| PC Windows (`DESKTOP-8IUGODI`) | MSI MS-7B17 | Poste d'administration (SSH, kubectl, k9s) | En service |

## Réseau (baux statiques Livebox)

| Machine | IP | MAC | Remarque |
|---|---|---|---|
| PROD-01 | 192.168.1.16 | C8:FF:BF:0B:32:95 | port RJ45 **gauche** (`enp3s0`) ; nom affiché « prod-1 » dans la Livebox |
| dev-linux | 192.168.1.19 | 38:7C:76:4F:B0:DA | |
| Home Assistant | 192.168.1.26 | 20:F8:3B:03:E0:97 | |
| PC Windows | 192.168.1.31 | 00:D8:61:17:BC:FB | |
| `pprod-01` (N100) | 192.168.1.51 | E8:FF:1E:D4:F6:07 | `enp1s0` ; ex-`gbaubu02p` ; réinstallé en phase 7 (ADR-026) |

Connexion : `ssh prod-01` / `ssh pprod-01` depuis le PC Windows ou dev-linux (voir [runbook socle OS](docs/runbooks/socle-os.md)).

## Kubernetes

| | |
|---|---|
| Cluster | K3s v1.36.5, mono-nœud, contexte **`prod-01`** |
| API | `https://k3s.prod.gba-lab.win:6443` (LAN uniquement) |
| Applications | `https://<app>.prod.gba-lab.win` (Traefik, certificat wildcard Let's Encrypt par défaut — ADR-022) |
| Certificats | cert-manager, guichets `letsencrypt-staging` / `letsencrypt-prod`, wildcard `kube-system/wildcard-prod-tls` renouvelé automatiquement |
| Postes | PC Windows (contexte unique `prod-01`) · dev-linux (défaut `k3d-dev-local`, PROD-01 **toujours** en `--context prod-01`) |
| Déployer une app | `helm upgrade --install <projet> oci://ghcr.io/gaelbasta/charts/plateforme --version 0.1.0 -n <projet> --create-namespace -f deploy/values-prod.yaml --kube-context prod-01 --wait` ([runbook](docs/runbooks/deployer-une-app.md)) |
| Accès | LAN uniquement (en 4G : injoignable, voulu) ; extérieur via Tailscale en phase 12 |
| Apps en service | **wiki** — https://wiki.prod.gba-lab.win (repo `gaelbasta/wiki`, ADR-024, ADR-025) · **prism** — https://prism.prod.gba-lab.win (repo PRISM, **1.0.0 avec les vraies données** depuis le 2026-10-14) |
| Sauvegardes | chaque nuit à 3 h vers `pprod-01` (restic, append-only), entretien le dimanche à 5 h — [runbook](docs/runbooks/sauvegarde-et-restauration.md) |
| Images privées | secret `ghcr-pull` dans le namespace du projet (token `k3s-prod-01-pull`, ADR-024) |
| Tests de fumée | sans Helm : `kubectl --context prod-01 apply -f tests/smoke-whoami.yaml` → https://test.prod.gba-lab.win · avec le chart : `tests/values-smoke-prod.yaml` → https://smoke.prod.gba-lab.win |

## Arborescence du repo

| Dossier | Contenu |
|---|---|
| `docs/` | architecture, glossaire, standard d'hébergement, runbooks |
| `.nav.yml` (racine, `docs/`, `docs/runbooks/`) | ordre du menu de ce repo dans le wiki (ADR-024) |
| `k3s/` | configuration K3s versionnée |
| `charts/` | chart Helm **plateforme** (profils app/static), publié sur `oci://ghcr.io/gaelbasta/charts/plateforme` |
| `platform/` | briques communes du cluster, une par dossier : valeurs Helm (`values-prod.yaml`) et manifestes de configuration (cert-manager, Traefik…) |
| `scripts/` | reconstruction : `socle-os.sh` (PROD-01 et `pprod-01`), `install-k3s.sh`, `coffre-sauvegardes.sh` (`pprod-01`, ADR-028), `sauvegarde-prod-01.sh` (PROD-01, ADR-029), `telegraf.sh` + `telegraf-etat.sh` (ADR-031) |
| `monitoring/` | configuration Telegraf de chaque serveur (ADR-031) |
| `tests/` | tests de fumée (manifeste brut, valeurs du chart pour k3d et prod) |
