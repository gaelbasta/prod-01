# Prompt de reprise — chantier PROD-01

> **Usage** : pour reprendre le chantier dans une **nouvelle conversation Claude**, copier-coller tout le bloc ci-dessous comme premier message, et **joindre le ZIP du repo** (ou au minimum `README.md`, `ROADMAP.md`, `DECISIONS.md`).
> **À tenir à jour** : la section « Où on en est » à la fin de chaque phase.

---

```text
Bonjour Claude. On reprend le chantier PROD-01 : mon serveur de production maison.
Je joins le repo prod-01 (ZIP). Lis d'abord README.md, ROADMAP.md et DECISIONS.md :
ils sont la source de vérité. Ne contredis pas une décision (ADR) sans le signaler
et proposer un nouvel ADR.

## Contexte
- Serveur : PROD-01 = GMKtec K8 Plus (Ryzen 7 8845HS, 32 Go, NVMe 1 To),
  Ubuntu Server 26.04.1 LTS, IP 192.168.1.16, K3s v1.36.5 mono-nœud.
- Postes : PC Windows (PowerShell) et dev-linux (Ubuntu, VS Code Remote SSH).
  Connexion : `ssh prod-01` depuis les deux (clés id_ed25519_prod_01).
- Kubernetes : contexte `prod-01`. Sur dev-linux, le contexte par défaut est
  `k3d-dev-local` (dev local) → PROD-01 TOUJOURS ciblé explicitement
  (`--context prod-01` / `--kube-context prod-01`).
- Domaine : gba-lab.win (Cloudflare). `*.prod.gba-lab.win` → 192.168.1.16
  (DNS only). La Livebox ne bloque pas le rebinding (testé).
- Repo : github.com/gaelbasta/prod-01 (privé), copie de travail
  ~/claude-projects/prod-01 sur dev-linux (~/projects est réservé aux projets Codex).
- N100 (gbaubu02p, 192.168.1.51) : future PPROD, à réinstaller avec scripts/.

## Ma façon de travailler (important)
- Je ne suis pas expert Git ni Kubernetes : guide-moi UNE ÉTAPE À LA FOIS,
  avec une explication courte (ELI5) de ce que fait chaque commande.
- Je colle les sorties des commandes ; attends-les avant l'étape suivante.
- Pour toute modif risquée (SSH, pare-feu…) : prévoir le retour arrière et
  garder une session ouverte.
- Rappelle-moi de vérifier le nom de machine dans l'invite (gael@prod-01 vs
  gael@dev-linux) : je me suis déjà trompé.
- Documentation : chaque décision → ADR dans DECISIONS.md ; chaque opération
  → runbook écrit à partir de ce que j'ai RÉELLEMENT fait (quoi / comment /
  vérifier / revenir en arrière). Livraison en pack ZIP du repo complet,
  que je dézippe dans ~/claude-projects puis git add/commit/push.
- Déploiements : Helm, manuels, depuis dev-linux ou Windows (ADR-021) ;
  un chart plateforme commun (profils app/static) + values-<env>.yaml par projet.

## Où on en est
- Phases 0 à 4 : ✅ (préparation, audit matériel, Ubuntu, socle OS, K3s +
  pare-feu + postes d'admin + test de fumée whoami).
- Prochaine : PHASE 5 — HTTPS + chart plateforme :
  1. token API Cloudflare (droits minimaux : Zone.DNS:Edit sur gba-lab.win)
  2. cert-manager (Helm) + ClusterIssuer Let's Encrypt (DNS-01 Cloudflare),
     d'abord en staging puis en production
  3. certificat wildcard *.prod.gba-lab.win, servi par Traefik par défaut
  4. chart Helm plateforme (profils app / static), testé d'abord sur
     k3d-dev-local puis déployé sur prod-01
  5. test : https://test.prod.gba-lab.win avec cadenas valide
- Ensuite : phase 6 wiki (MkDocs, agrège les docs/ des projets),
  phase 7 sauvegardes (restic → disque 3,5" sur le N100), phase 8 PRISM.
```
