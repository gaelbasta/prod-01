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

## Règles du repo

1. **Une décision = une entrée dans `DECISIONS.md`**, avec le pourquoi. Pas de décision orale.
2. **Une opération faite deux fois = un runbook.** Le runbook est écrit à partir de ce qui a *réellement* été fait, pas de la théorie.
3. **Aucun secret dans ce repo** (mots de passe, tokens, clés privées). Seulement l'endroit où ils sont rangés.
4. Chaque runbook répond à 4 questions : *quoi*, *comment* (commandes exactes), *comment vérifier*, *comment revenir en arrière*.

## Machines

| Nom | Matériel | Rôle | État |
|---|---|---|---|
| PROD-01 | GMKtec K8 Plus — Ryzen 7 8845HS, 32 Go, NVMe 1 To | Production | Socle OS prêt |
| N100 (`gbaubu02p`) | Mini-PC Intel N100 | PPROD + cible de sauvegarde transitoire | À réinstaller après PROD-01 |
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
| N100 (`gbaubu02p`) | 192.168.1.51 | E8:FF:1E:D4:F6:07 | ancien K3s |

Connexion : `ssh prod-01` depuis le PC Windows ou dev-linux (voir [runbook socle OS](docs/runbooks/socle-os.md)).

## Kubernetes

| | |
|---|---|
| Cluster | K3s v1.36.5, mono-nœud, contexte **`prod-01`** |
| API | `https://k3s.prod.gba-lab.win:6443` (LAN uniquement) |
| Applications | `http(s)://<app>.prod.gba-lab.win` (Traefik) |
| Postes | PC Windows (contexte unique `prod-01`) · dev-linux (défaut `k3d-dev-local`, PROD-01 **toujours** en `--context prod-01`) |
| Test de fumée | `kubectl --context prod-01 apply -f tests/smoke-whoami.yaml` → http://test.prod.gba-lab.win |

## Arborescence du repo

| Dossier | Contenu |
|---|---|
| `docs/` | architecture, glossaire, standard d'hébergement, runbooks |
| `k3s/` | configuration K3s versionnée |
| `scripts/` | reconstruction : `socle-os.sh`, `install-k3s.sh` |
| `tests/` | tests de fumée |
