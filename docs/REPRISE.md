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
- Phases 0 à 8 : ✅ (niveau 1 terminé) (préparation, audit matériel, Ubuntu, socle OS, K3s + pare-feu
  + postes d'admin, HTTPS + chart plateforme, wiki, sauvegardes, PRISM).
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
  - Accès en 4G impossible sans Tailscale : voulu (IP privée) → résolu en phase 12 (ADR-033).
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
- Phase 8 ✅ 2026-10-14 — PRISM en production avec les vraies données :
  - Base d'essai effacée (helm uninstall + delete pvc, secrets conservés), redéploiement,
    /data/sauvegardes recréé ; 4 CSV réels importés (2026 complet ; 2 exports PayPal à refaire).
  - Sauvegarde manuelle immédiate : instantané restic 9f73631e (vraies données, avant 1.0.0).
  - PRISM 1.0.0 (commit PRISM 92af28d, image ghcr.io/gaelbasta/prism:1.0.0, sans migration de
    base) : révision Helm 2 ; retour arrière possible : helm rollback prism 1 (0.9.0).
  - Volume prism-data : pvc-ffe792d0-… (l'exclusion restic *_prism_prism-data/prism.sqlite* suit).
  - PRISM garde lui-même 14 copies quotidiennes + 12 mensuelles dans /data/sauvegardes
    (fait sa copie vers 3 h 05). Contrat : `k3s kubectl -n prism exec deploy/prism --
    node src/serveur/sauvegarder.ts` (code 0) ; jamais prism.sqlite/-wal/-shm.
- Mises à jour (analysé le 2026-10-14) : unattended-upgrades fonctionne (libx11 installé le
  13/10) ; les 11 correctifs de sécurité vus le 14/10 sont arrivés après le passage de 6 h 06 →
  ✅ installés le 15/10 à 6 h 07 (« All upgrades installed », pas de redémarrage requis).
  Avertissement sans gravité « distro-info-data outdated » (corrigé par le prochain apt upgrade manuel).
  Les paquets de resolute-updates (tzdata, open-vm-tools…) ne s'installent jamais seuls (voulu,
  ADR-018) → `sudo apt upgrade` manuel ~1×/mois, à ajouter au runbook socle-os. open-vm-tools
  inutile sur machine physique (à désinstaller un jour). 2 mises à jour de firmware (fwupdmgr)
  et « 4 not upgraded » sur pprod-01 : à regarder.
- ✅ 15/10 : 1re sauvegarde automatique de 3 h réussie (instantané 8f9308e8). Contrôle :
  `ssh -t prod-01 'sudo cat /var/lib/sauvegarde-prod-01/derniere-tentative'` (sudo obligatoire).
- Wiki reconstruit le 14/10 après le push de la phase 8.
- Phase 11 ✅ 2026-10-15 — surveillance (ADR-031, runbook surveillance.md) :
  - Telegraf 1.40.2 (dépôt InfluxData, clé copiée de dev-linux) sur PROD-01 et pprod-01 →
    InfluxDB 192.168.1.26:8087, bucket infrastructure ; tokens telegraf-prod-01 /
    telegraf-pprod-01 (écriture seule ; gestionnaire + /etc/default/telegraf).
  - Configs versionnées monitoring/telegraf/<serveur>.conf, installées par scripts/telegraf.sh
    (teste config et règle sudo AVANT de les poser) ; mesures maison scripts/telegraf-etat.sh.
  - pprod-01 surveille PROD-01 de l'extérieur : PRISM /healthz, wiki, certificat wildcard.
    NOUVELLE APP = ajouter son URL dans monitoring/telegraf/pprod-01.conf (PLATFORM_STANDARD 5).
  - Grafana : dossier prod-01, groupe prod-01-1m, 11 règles (export monitoring/grafana/
    alertes-prod-01.yaml), contact point « Home Assistant — dev-linux » (webhook HA → téléphone).
    Test réel « PROD-01 — plus de données » réussi (notification reçue).
  - Pièges : sudo-rs (Ubuntu 26.04) refuse Defaults!…!logfile ; exec Telegraf ≥ 1.39 =
    commands = [["…"]] ; Flux + group()/max() → finir par keep(columns: ["_time","_value"]).
  - Reste éventuel : un dashboard Grafana « PROD-01 » (confort, non bloquant).
- Phase 10 ✅ 2026-10-15 — Sealed Secrets (ADR-032, runbook secrets.md, partie « En deux minutes ») :
  - Contrôleur 0.40.0 (chart 2.20.0, catalogue https://bitnami.github.io/sealed-secrets — l'ancienne
    adresse bitnami-labs.github.io répond 404) dans kube-system, nommé sealed-secrets-controller ;
    valeurs platform/sealed-secrets/values-prod.yaml ; renouvellement de clé DÉSACTIVÉ (une seule clé).
  - Clé privée kube-system/sealed-secrets-key72g5d : dans la base K3s (restic) + gestionnaire
    « Sealed Secrets – clé prod-01 » (fichier joint, sha256 938cd832…). Restauration TESTÉE sur k3d avec
    la copie du gestionnaire. Certificat public commité : platform/sealed-secrets/prod-01-cert.pem
    (expire le 12/10/2036). kubeseal 0.40.0 sur dev-linux seulement (pas sur le PC Windows).
  - 4 secrets migrés sans coupure (empreinte avant = après) : secrets/prod-01/{cert-manager/
    cloudflare-api-token, wiki/ghcr-pull, prism/ghcr-pull, prism/prism-secrets}.yaml, tous SYNCED True.
  - Règle : changer un secret = refaire l'enveloppe (kubeseal --cert), commit, kubectl apply.
    ⚠️ Supprimer un SealedSecret supprime le Secret. PRISM ne relit son mot de passe qu'au redémarrage.
  - Points ouverts : mot de passe PRISM (10 caractères) CONSERVÉ — choix de Gael le 15/10 ;
    secrets.md C (changer une valeur) pas encore pratiquée ; docs/ du repo PRISM et du repo wiki
    décrivent encore la création des secrets à la main → à mettre à jour ; chart plateforme 0.2.0 :
    commentaires « secrets créés à la main » à corriger.
- Phase 12 ✅ 2026-10-15 — Tailscale (ADR-033, runbook acces-distant-tailscale.md) :
  - Tailnet tail91cc22.ts.net (compte Google, 1 utilisateur) : homeassistant (annonce déjà 192.168.1.0/24
    + IPv6, exit node), prod-01 (100.110.247.64), téléphone redmi-note-12-pro-5g (100.118.137.26).
  - PROD-01 : Tailscale 1.104.1 (dépôt pkgs.tailscale.com, MAJ manuelles) ; `tailscale up --hostname=prod-01
    --advertise-routes=192.168.1.16/32 --accept-dns=false --accept-routes=false` ; route approuvée,
    expiration désactivée. Mêmes URL dedans/dehors, PRISM compris. Pare-feu inchangé (admin = LAN seul).
  - Test 4G réussi (tcpdump sur tailscale0, `active; direct`). Piège : valider le lien de connexion en
    moins de 2 min, sinon « http 410 » → Ctrl+C et relancer.
  - AVANT d'ajouter Estelle/Anna : règles d'accès (famille → 192.168.1.16:80/443 seulement). Aujourd'hui,
    via le /24 de HA, le SSH de PROD-01 est joignable depuis le tailnet (OK tant que seul utilisateur).
- PROJET DÉDIÉ À CRÉER (hors prod-01) : audit/optimisation de Home Assistant — alerte « plus de
  données » absente pour dev-linux et le PC Windows, contact point à renommer, webhook à protéger, Tailscale de HA à mettre à jour (1.96.4) et
  ses routes (/24 + exit node) à revoir avant l'arrivée de la famille sur le tailnet.
- PROCHAINE PHASE (niveau 2) : 13 Landing page (Homepage). Puis niveau 3 (14 PPROD…).
- Chart plateforme 0.2.0 à prévoir : enableServiceLinks: false, --context dans les NOTES, commentaires secrets (ADR-032)
  (voir charts/plateforme/README.md).
```
