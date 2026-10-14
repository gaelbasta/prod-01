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
- pprod-01 (N100, ex-gbaubu02p, 192.168.1.51) : réinstallé en phase 7 (ADR-026),
  cible de sauvegarde (ADR-027), future PPROD (phase 14). `ssh pprod-01`.

## Ma façon de travailler (important)
- Je ne suis pas expert Git ni Kubernetes : guide-moi UNE ÉTAPE À LA FOIS,
  avec une explication courte (ELI5) de ce que fait chaque commande.
- Je colle les sorties des commandes ; attends-les avant l'étape suivante.
- Pour toute modif risquée (SSH, pare-feu…) : prévoir le retour arrière et
  garder une session ouverte. Présenter le retour arrière dans un encadré
  « ⛔ NE PAS EXÉCUTER — seulement en cas de problème », jamais comme un
  bloc de commandes à la suite des vérifications.
- Règle Git : écrire le fichier → git diff → commit + push → PUIS appliquer.
- Rappelle-moi de vérifier le nom de machine dans l'invite (gael@prod-01 vs
  gael@dev-linux) : je me suis déjà trompé.
- Documentation : chaque décision → ADR dans DECISIONS.md ; chaque opération
  → runbook écrit à partir de ce que j'ai RÉELLEMENT fait (quoi / comment /
  vérifier / revenir en arrière). Livraison en pack ZIP du repo complet,
  que je dézippe dans ~/claude-projects puis git add/commit/push.
- Déploiements : Helm, manuels, depuis dev-linux ou Windows (ADR-021) ;
  un chart plateforme commun (profils app/static) + values-<env>.yaml par projet.

## Où on en est
- Phases 0 à 7 : ✅ (préparation, audit matériel, Ubuntu, socle OS, K3s + pare-feu
  + postes d'admin, HTTPS + chart plateforme, wiki, sauvegardes).
- Phase 5 en bref (ADR-022, ADR-023) : cert-manager v1.21.2, wildcard
  *.prod.gba-lab.win servi par défaut par Traefik, redirection HTTP → HTTPS ;
  chart plateforme 0.1.0 sur oci://ghcr.io/gaelbasta/charts/plateforme (privé).
  helm registry login ghcr.io fait sur dev-linux ; PAS ENCORE sur le PC Windows.
- Phase 6 en bref (2026-10-10, ADR-024 et ADR-025, runbook wiki.md) :
  - https://wiki.prod.gba-lab.win : MkDocs 1.6.1 figé, thème Material 9.7.7
    (ADR-025, après un essai readthedocs), plugin awesome-nav 3.3.0 (ordre du menu
    par fichiers .nav.yml dans les repos), extensions superfences + truly_sane_lists
    pour un rendu identique à VS Code. En prod : image 2026.10.10-1715, révision 3.
  - Repo gaelbasta/wiki (privé, ~/claude-projects/wiki) : projets.txt liste les
    repos publiés ; scripts/construire.sh les clone depuis GitHub et construit
    l'image ghcr.io/gaelbasta/wiki:<AAAA.MM.JJ-HHMM> (privée) ; déployé avec le
    chart plateforme, profil static. Pas de mise à jour automatique.
  - Images privées : token k3s-prod-01-pull (read:packages, sans expiration),
    secret ghcr-pull par namespace. docker login ghcr.io fait sur dev-linux.
  - Accès en 4G impossible : voulu (IP privée) → Tailscale en phase 12.
- Phase 7 ✅ 2026-10-14 — sauvegardes (ADR-026 à ADR-030, runbook sauvegarde-et-restauration.md) :
  - pprod-01 (Beelink N100, 192.168.1.51) = COFFRE : disque Seagate IronWolf 4 To n° WW6AR4CY
    (boîtier USB CENMATE, puce ASMedia) monté /srv/sauvegardes (UUID d5c73bd1-…, nofail,
    chattr +i sur le point de montage vide) ; rest-server 0.14.0 (paquet apt, commande
    /usr/bin/restic-rest-server, notre service rest-server.service) --append-only
    --private-repos, port 8000 ouvert à 192.168.1.16 seul (ufw) ; utilisateur système restic.
  - PROD-01 : `sudo sauvegarde-prod-01 lancer` chaque nuit à 3 h (timer) : copie PRISM →
    copie K3s (sqlite3 .backup) → restic backup → traces /var/lib/sauvegarde-prod-01/
    {derniere-tentative,derniere-reussite}. Dépôt rest:http://192.168.1.51:8000/prod-01/
    (id 362bcd9da7). Raccourci : `sudo sauvegarde-prod-01 restic <commande>`.
  - pprod-01 : entretien le dimanche à 5 h (forget --prune 14 j/8 sem/12 mois/3 ans +
    check --read-data, en utilisateur restic). Raccourci : `sudo coffre-sauvegardes restic …`.
  - Secrets : gestionnaire « restic – dépôt prod-01 » et « rest-server pprod-01 – prod-01 » ;
    PROD-01 /etc/restic/{motdepasse,prod-01.env} ; pprod-01 /etc/restic/prod-01.motdepasse,
    /etc/rest-server/.htpasswd.
  - Validé : 3 tests de restauration (fichier /etc, base K3s, volume d'app détruit puis
    restauré — app de test tests/values-restauration-prod.yaml) + garde-fous (pare-feu,
    append-only 403, disque absent, redémarrage). Postes nettoyés (numobserver).
- À traiter (hors phase) : PROD-01 annonçait le 2026-10-14 « 11 standard security updates »
  en attente malgré unattended-upgrades (ADR-018) → comprendre pourquoi ; 2 mises à jour de
  firmware signalées (fwupdmgr) ; « 4 not upgraded » sur pprod-01.
- PHASE 8 EN COURS : PRISM déployé le 2026-10-11 sur https://prism.prod.gba-lab.win
  (image 0.9.0, chart 0.1.0, révision 1, volume prism-data 1 Gi, secrets ghcr-pull +
  prism-secrets) avec des DONNÉES D'ESSAI. Phase 7 validée → vraies données AUTORISÉES
  (prochaine étape). PRISM écrit une copie par jour dans /data/sauvegardes
  (prism-AAAA-MM-JJ.sqlite) : vérifier que PRISM supprime les anciennes (volume 1 Gi).
  Contrat sauvegarde : le script restic de PROD-01 appelle d'abord
  `k3s kubectl -n prism exec deploy/prism -- node src/serveur/sauvegarder.ts`
  (code 0 = copie cohérente dans /data/sauvegardes) ; seuls les fichiers de
  /data/sauvegardes sont fiables, jamais prism.sqlite/-wal/-shm.
- Chart plateforme 0.2.0 à prévoir : enableServiceLinks: false, --context dans les NOTES
  (voir charts/plateforme/README.md).
```
