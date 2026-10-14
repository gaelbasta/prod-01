# Décisions d'architecture (ADR)

Chaque décision : **contexte → décision → pourquoi → conséquences**.
Statuts : **Acceptée** · **Proposée** (à valider pendant la phase indiquée) · **Ouverte** (pas encore tranchée).
On ne supprime jamais une décision : si elle change, on en écrit une nouvelle qui la remplace.

---

## ADR-001 — Le K8 Plus devient PROD-01
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : le GMKtec K8 Plus (Ryzen 7 8845HS, 32 Go, NVMe 1 To) est le serveur de production principal. Il remplace le mini-PC N100.
- **Pourquoi** : bien plus de puissance et de RAM, 2 slots NVMe, 2 cartes réseau 2,5 GbE.
- **Conséquences** : le N100 change de rôle (voir ADR-014).

## ADR-002 — Ubuntu Server 26.04.1 LTS
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : Ubuntu Server 26.04.1 LTS, installation minimale sans interface graphique.
- **Pourquoi** : même OS que dev-linux, donc mêmes commandes et mêmes réflexes. Support long terme.

## ADR-003 — Partitionnement LVM
- **Date** : 2026-10-09 · **Statut** : Acceptée (appliquée le 2026-10-09)
- **Décision** : `/boot/efi` 1 Go, `/boot` 2 Go (ext4), puis LVM `vg0` (~950 Go) : `root` 80 Go sur `/`, `rancher` 350 Go sur `/var/lib/rancher` (K3s et données des apps), ~520 Go laissés libres.
- **Pourquoi** : si les données des apps remplissent leur volume, le système continue de fonctionner. L'espace libre permet d'agrandir un volume sans réinstaller.
- **Conséquences** : l'installeur Ubuntu n'utilise par défaut qu'une partie du disque → réglage manuel pendant l'installation.

## ADR-004 — K3s mono-nœud
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : K3s sur un seul nœud, avec Traefik (fourni avec K3s) comme point d'entrée HTTP et le stockage local de K3s.
- **Pourquoi** : Kubernetes complet mais léger ; tout est inclus par défaut, rien à assembler.
- **Conséquences** : pas de haute disponibilité (si PROD-01 tombe, tout tombe) — acceptable pour un usage personnel. La config K3s est versionnée dans ce repo.

## ADR-005 — Un seul standard d'hébergement
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : tout projet est hébergé sur K3s selon deux profils : **app** (conteneur + éventuelle base) ou **static** (fichiers servis par nginx). Pas de Docker Compose ni d'hébergement à côté.
- **Pourquoi** : une seule méthode à connaître, documenter et sauvegarder.
- **Conséquences** : décrit dans `docs/PLATFORM_STANDARD.md` et intégré à la méthode projet (PROJECT_BOOTSTRAP).

## ADR-006 — Déploiement : manuel d'abord, GitOps ensuite
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : niveau 1 : `kubectl apply -k <dossier>` depuis ce repo. Niveau 2 : Argo CD surveille ces mêmes dossiers et déploie automatiquement.
- **Pourquoi** : moins de choses à apprendre au départ, sans rien à refaire plus tard.

> ⚠️ ADR-006 est **remplacée par ADR-021** (2026-10-10).

## ADR-007 — Registre d'images : GHCR
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : images Docker privées sur GitHub Container Registry. Build sur dev-linux, puis éventuellement GitHub Actions.
- **Conséquences** : le cluster utilise un token GitHub en lecture seule. Jamais de données dans une image.

## ADR-008 — Gestion des secrets
- **Date** : 2026-10-09 · **Statut** : Proposée
- **Décision** : niveau 1 : secrets créés à la main avec kubectl, leur emplacement documenté (pas leur valeur). Niveau 2 : Sealed Secrets (secrets chiffrés stockables dans Git).
- **Conséquences** : la clé de Sealed Secrets devra être sauvegardée, sinon les secrets deviennent illisibles.

## ADR-009 — Nom de domaine et HTTPS
- **Date** : 2026-10-09 · **Statut** : Acceptée — domaine **`gba-lab.win`** (déjà détenu, DNS chez Cloudflare), précisé le 2026-10-10
- **Noms** : `*.prod.gba-lab.win` → PROD-01 (192.168.1.16) ; `*.pprod.gba-lab.win` → N100 (plus tard). Enregistrements en **DNS only** (nuage gris) : le proxy Cloudflare ne peut pas joindre une IP privée.
- **Pourquoi `.prod.` plutôt que `*.gba-lab.win`** (discuté le 2026-10-10) : le domaine servira à d'autres usages. Le sous-domaine donne une frontière lisible (*tout ce qui est en `.prod.` est privé*), évite que des noms oubliés ou mal tapés atterrissent silencieusement sur PROD-01, et laisse la racine libre pour d'autres machines ou d'éventuels services publics (chacun avec un ADR).
- **Contexte** : la Livebox 4 fait le DNS du LAN mais ne permet pas de créer des noms personnalisés. Pas d'IP publique fixe.
- **Décision** : acheter un nom de domaine. Enregistrement DNS public `*.prod.<domaine>` qui pointe vers l'**IP privée** de PROD-01. Certificat wildcard Let's Encrypt obtenu par validation DNS.
- **Pourquoi** : de vraies URL en HTTPS sur tous les appareils sans rien installer dessus. HTTPS est nécessaire pour qu'une app soit installable sur téléphone (PWA). Rien n'est exposé : une IP privée est injoignable depuis Internet.
- **Conséquences** : l'absence d'IP fixe n'a **aucun impact** (on ne publie jamais l'IP publique).
- **Mise en œuvre (2026-10-10)** : enregistrement Cloudflare `A  *.prod → 192.168.1.16`, « DNS only - reserved IP », commentaire « PROD-01 - LAN uniquement (ADR-009) ».
- **Test anti-rebinding (2026-10-10)** : ✅ la Livebox **ne bloque pas**. `nslookup test.prod.gba-lab.win` répond `192.168.1.16` via la Livebox comme via `1.1.1.1`. Aucun serveur DNS local nécessaire.

## ADR-010 — Accès hors LAN via Tailscale
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : Tailscale sur PROD-01. Accès réservé aux appareils de la famille. Aucun port ouvert sur la Livebox.
- **Conséquences** : une exposition publique éventuelle (Tailscale Funnel, Cloudflare Tunnel) fera l'objet d'un ADR dédié, au cas par cas. PRISM reste réservé au LAN.

## ADR-011 — Wiki : docs-as-code
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : documentation en Markdown dans Git, rendue en site par MkDocs (ou son successeur, à vérifier à l'installation). Le wiki **agrège** le dossier `docs/` de chaque projet.
- **Pourquoi** : la doc vit avec le code, est versionnée, et Claude/Codex peuvent l'écrire directement.

> Outil et organisation précisés par **ADR-024** (2026-10-10) : MkDocs 1.6 figé, repo `wiki` ; thème Material (**ADR-025**).

## ADR-012 — Sauvegardes
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : restic (chiffré) depuis PROD-01 vers le disque 3,5" branché sur le **N100**, en attendant le NAS. Le service de sauvegarde tourne sur le système du N100, hors K3s.
- **Contenu** : données des apps (avec dump propre des bases), base de K3s, `/etc`, clés de secrets.
- **Pourquoi** : une sauvegarde sur une autre machine survit à la perte de PROD-01.
- **Conséquences** : un seul disque = pas de redondance (transitoire). Une sauvegarde n'est validée qu'après un **test de restauration**. Le mot de passe restic est conservé hors de PROD-01.

> Mise en œuvre précisée par **ADR-027** (2026-10-10) : rest-server en append-only, mot de passe aussi dans le gestionnaire de mots de passe ; puis par **ADR-028** (2026-10-13) : paquets Ubuntu, garde-fou disque, un sous-dossier par déposant.

## ADR-013 — Surveillance par Home Assistant
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : HA surveille PROD-01 depuis l'extérieur : ping, check HTTP de chaque app, métriques de l'hôte. Alerte prioritaire : **absence de données**.
- **Pourquoi** : HA existe déjà et est une machine distincte de PROD-01.

## ADR-014 — Le N100 devient la PPROD
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : le N100 est réinstallé (ISO propre) après PROD-01 et devient la PPROD.
- **Conditions** : identique à la PROD par construction (mêmes scripts, mêmes manifestes, overlays `pprod`/`prod`) ; **aucune donnée réelle** (PRISM avec données de test).
- **Conséquences** : la réinstallation du N100 sert de premier test de reconstruction. Le disque de sauvegarde devra être remonté après la réinstallation.

> Précisée par **ADR-026** (2026-10-10) : réinstallation (OS + socle) avancée en phase 7, avant l'arrivée du disque ; nom `pprod-01`.

## ADR-016 — Secure Boot désactivé
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Contexte** : Secure Boot est désactivé d'usine. Le BIOS (08/2025) peut ne pas contenir les clés Microsoft récentes utilisées par les nouveaux chargeurs de démarrage Linux.
- **Décision** : laisser Secure Boot désactivé.
- **Pourquoi** : il protège surtout contre une personne ayant un accès physique à la machine, risque négligeable à la maison. L'activer peut empêcher Ubuntu de démarrer pour une question de clés, sans bénéfice réel.
- **Conséquences** : à réévaluer si une mise à jour BIOS GMKtec apporte les nouvelles clés.

## ADR-017 — Accès SSH par clé uniquement
- **Date** : 2026-10-10 · **Statut** : Acceptée (appliquée)
- **Décision** : connexion SSH uniquement par clé ED25519, une clé par poste (`id_ed25519_prod_01` sur le PC Windows et sur dev-linux). Mots de passe et connexion `root` refusés en SSH (`/etc/ssh/sshd_config.d/10-prod01.conf`).
- **Pourquoi** : un mot de passe peut être deviné ou volé ; une clé privée ne quitte jamais le poste.
- **Conséquences** : le mot de passe de `gael` reste nécessaire pour `sudo` et la console locale (écran + clavier = accès de secours). Perte de toutes les clés = intervention en console.

## ADR-018 — Mises à jour : sécurité automatique, redémarrage manuel
- **Date** : 2026-10-10 · **Statut** : Acceptée
- **Décision** : `unattended-upgrades` installe chaque jour les correctifs de sécurité. Aucun redémarrage automatique.
- **Pourquoi** : les correctifs arrivent sans intervention, mais une coupure des services reste toujours décidée et constatée par Gael.
- **Conséquences** : surveiller la présence de `/var/run/reboot-required` (alerte Home Assistant prévue en phase 11).

## ADR-019 — Pas de swap
- **Date** : 2026-10-10 · **Statut** : Acceptée (appliquée)
- **Décision** : fichier `/swap.img` (8 Go, créé par l'installeur) supprimé.
- **Pourquoi** : Kubernetes gère la mémoire des applications et préfère un nœud sans swap ; 29 Go de RAM disponibles suffisent largement.

## ADR-020 — Pare-feu de l'hôte (ufw), activé avec K3s
- **Date** : 2026-10-10 · **Statut** : Acceptée (appliquée)
- **Décision** : le pare-feu (ufw) sera activé avec K3s, en ouvrant SSH, HTTP/HTTPS, l'API Kubernetes et les réseaux internes de K3s.
- **Pourquoi** : un pare-feu activé avant K3s sans ses règles bloque le réseau interne des pods. Le serveur n'est de toute façon pas exposé à Internet (aucun port ouvert sur la Livebox, pare-feu IPv6 de la box actif).
- **Mise en œuvre (2026-10-10)** : `ufw` actif — par défaut tout refusé en entrée ; ouverts : 22 et 6443 depuis `192.168.1.0/24` uniquement, 80/443 depuis partout, réseaux internes K3s `10.42.0.0/16` (pods) et `10.43.0.0/16` (services). Testé : metrics-server, redémarrage de coredns, sortie Internet depuis un pod, SSH.
- **Limite connue** : le trafic vers les applications (80/443) est aiguillé par Kubernetes avant `ufw`. Le pare-feu protège le serveur lui-même ; la non-exposition des applications repose sur la Livebox (aucune redirection de port, pare-feu IPv6 actif).

## ADR-021 — Déploiement par Helm, manuel, depuis dev-linux ou le PC Windows
- **Date** : 2026-10-10 · **Statut** : Acceptée · **Remplace** : ADR-006
- **Contexte** : Gael préfère déployer manuellement en PROD et en PPROD, en complétant un fichier de valeurs puis en lançant une seule commande.
- **Décision** :
  1. **Un chart Helm commun** (« chart plateforme ») porte les deux profils `app` et `static` (ADR-005). Chaque projet ne fournit qu'un **fichier de valeurs par environnement** (`values-prod.yaml`, `values-pprod.yaml`), sans écrire de YAML Kubernetes.
  2. **Une seule commande**, rejouable : `helm upgrade --install <projet> <chart> -n <projet> --create-namespace -f values-prod.yaml --kube-context prod-01`.
  3. Les applications tierces (cert-manager, wiki, Homepage…) s'installent aussi par leur chart Helm officiel, avec leur fichier de valeurs versionné dans ce repo.
- **Règles** :
  - **Le fichier de valeurs déployé est toujours commité dans Git** (sinon la prod ne correspond plus à rien de connu).
  - **Aucun secret dans un fichier de valeurs** : secrets créés à part (ADR-008).
  - **Contexte toujours explicite** (`--kube-context prod-01` ou `pprod`) pour ne jamais déployer sur le mauvais serveur.
- **Pourquoi** : une seule méthode pour tout (ADR-005), un geste simple, un historique et un retour arrière intégrés (`helm history`, `helm rollback`).
- **Conséquences** : Argo CD (phase 9) devient **optionnel**, à reconsidérer plus tard (il sait lui aussi déployer des charts Helm, rien ne serait perdu). Helm est installé sur le PC Windows et dev-linux en phase 4.

## ADR-022 — HTTPS : cert-manager, DNS-01 Cloudflare, un wildcard servi par défaut
- **Date** : 2026-10-10 · **Statut** : Acceptée (appliquée) · **Précise** : ADR-009, ADR-021
- **Contexte** : les apps de PROD-01 doivent être en HTTPS valide (PWA, ADR-009) alors que PROD-01 n'est **pas joignable depuis Internet** : Let's Encrypt ne peut donc pas venir vérifier par HTTP.
- **Décision** :
  1. **cert-manager v1.21.2**, installé par son chart Helm officiel (`oci://quay.io/jetstack/charts/cert-manager`), valeurs dans `platform/cert-manager/values-prod.yaml`.
  2. **Validation DNS-01 via Cloudflare** : cert-manager écrit un TXT temporaire `_acme-challenge.prod.gba-lab.win`. Token API dédié `cert-manager-prod-01`, droits **Zone.DNS:Edit + Zone.Zone:Read** limités à la zone `gba-lab.win` (le droit de lecture est nécessaire pour que cert-manager trouve la zone), sans filtre d'IP (IP publique non fixe) ni date d'expiration (une expiration bloquerait les renouvellements en silence). Vérification de propagation sur `1.1.1.1` / `1.0.0.1`, jamais la Livebox.
  3. **Deux guichets** (`ClusterIssuer`) : `letsencrypt-staging` (bac à sable, pour tester toute nouvelle config) et `letsencrypt-prod`. **Pas d'e-mail** de compte : facultatif, Let's Encrypt n'envoie plus d'alertes d'expiration depuis 2025.
  4. **Un seul certificat wildcard** `*.prod.gba-lab.win` (`kube-system/wildcard-prod-tls`), déclaré **certificat par défaut de Traefik** via le `TLSStore` nommé `default`. Les apps ne gèrent **aucun certificat** : leur Ingress contient seulement un bloc `tls:` sans `secretName` (le chart plateforme l'ajoutera).
  5. Les objets de configuration qui ne sont pas des charts (`ClusterIssuer`, `Certificate`, `TLSStore`) sont des manifestes versionnés dans `platform/<outil>/` et appliqués par `kubectl --context prod-01 apply -f`. Comme pour Helm : **commit avant application**.
- **Pourquoi** : DNS-01 est la seule validation possible sans exposer PROD-01. Un wildcard unique = une seule demande à Let's Encrypt (pas de quota consommé à chaque nouvelle app), zéro configuration TLS par app, et le nom des apps n'apparaît pas dans les journaux publics de certificats (Certificate Transparency).
- **Conséquences** :
  - Le token Cloudflare est conservé dans le gestionnaire de mots de passe ; dans le cluster : secret `cert-manager/cloudflare-api-token`, clé `api-token` (ADR-008). Perte du cluster = recréer ce secret puis réappliquer `platform/` ; tout le reste (clés de compte, certificat) se régénère seul.
  - Renouvellement automatique ~30 jours avant échéance (certificats de 90 jours). La surveillance de l'échéance revient à Home Assistant (phase 11).
  - La PPROD aura son propre wildcard `*.pprod.gba-lab.win` (même méthode, son propre token).
  - Redirection automatique HTTP → HTTPS : en place (ADR-023).
  - Hors du LAN (4G), les noms `*.prod` répondent `192.168.1.16` mais sont injoignables : comportement voulu, constaté le 2026-10-10 ; accès extérieur par Tailscale (ADR-010).

## ADR-023 — Chart plateforme : publié sur GHCR, redirection HTTPS globale, static = image nginx
- **Date** : 2026-10-10 · **Statut** : Acceptée (mise en œuvre en phase 5) · **Précise** : ADR-005, ADR-021
- **Décision** :
  1. **Le chart plateforme** est développé dans ce repo (`charts/plateforme/`) et **publié sur GHCR** en version figée (`oci://ghcr.io/gaelbasta/charts/plateforme`, `--version 0.1.0`). Chaque projet déploie avec une version explicite, notée dans l'en-tête de son `values-<env>.yaml`. **Une version publiée n'est jamais republiée** : toute modification du chart = nouvelle version.
  2. **Redirection HTTP → HTTPS globale**, configurée une fois dans Traefik (K3s `HelmChartConfig`, versionnée dans `platform/traefik/`). Le chart ne gère pas de redirection.
  3. **Profil static = une image** (nginx + fichiers du site, base conseillée `nginxinc/nginx-unprivileged`, port 8080) construite par le projet et poussée sur GHCR, exactement comme une app.
  4. Garde-fous dans le chart : valeurs inconnues refusées (`values.schema.json`, contre les fautes de frappe), image/tag/host obligatoires, `latest` interdit, volume de données **conservé** après `helm uninstall` (`helm.sh/resource-policy: keep`).
- **Pourquoi** :
  1. Une évolution du chart ne modifie jamais un projet « en douce » au prochain déploiement ; les postes n'ont pas besoin d'une copie du repo prod-01 ; même registre que les images (ADR-007).
  2. Une seule configuration pour toutes les apps, aucun oubli possible ; sans risque car les certificats sont validés par DNS (ADR-022), jamais par HTTP.
  3. Un seul parcours (build → GHCR → `helm upgrade`), retour arrière par version, rien à sauvegarder pour un site statique.
- **Conséquences** :
  - Les postes d'administration se connectent une fois à GHCR (`helm registry login ghcr.io`, token GitHub `read:packages`, et `write:packages` sur dev-linux pour publier). Le cluster, lui, ne télécharge jamais le chart (seulement les images).
  - Le chart est d'abord testé sur `k3d-dev-local` (`helm lint` puis déploiement) avant toute publication.
- **Mise en œuvre (2026-10-10)** :
  - Chart **0.1.0** publié (`sha256:8dfa83fc…f6f4078`), tag Git `plateforme-0.1.0`, paquet GHCR **privé**. Test `smoke` déployé sur PROD-01 depuis GHCR : HTTPS valide, redirection 308, mise à jour sans coupure (300/300).
  - Ajout de `shutdownDelaySeconds` (pause `preStop` de 5 s) après avoir **mesuré** 1 erreur 502/504 sur 300 requêtes pendant chaque mise à jour sans elle.
  - Redirection : `platform/traefik/helmchartconfig.yaml`. Syntaxe du chart Traefik 40 : `ports.web.http.redirections` (l'ancienne clé est ignorée sans erreur → toujours vérifier les arguments de Traefik).

## ADR-024 — Wiki : MkDocs 1.6 figé, thème readthedocs, repo `wiki` qui rassemble les docs
- **Date** : 2026-10-10 · **Statut** : Acceptée · **Précise** : ADR-011, ADR-005, ADR-023

> ⚠️ Le **thème** (point 1) est **remplacé par ADR-025** (Material + extensions) ; le reste de cet ADR s'applique.

- **Contexte** : ADR-011 demandait de vérifier à l'installation « MkDocs ou son successeur ». État au 2026-10-10 : MkDocs 1.6.1 (2024) est la dernière version stable ; **MkDocs 2.0** est en préversion et supprime les plugins ; l'équipe de Material for MkDocs développe désormais **Zensical**, encore en alpha (0.1.0 annoncée pour le 5 novembre 2026).
- **Décision** :
  1. **MkDocs 1.6.1 figé** (`requirements.txt` du repo `wiki`), avec son thème intégré **`readthedocs`** (préférence de Gael, habitué à ce rendu) et le plugin **awesome-nav 3.3.0** pour l'ordre du menu.
  2. **Un repo dédié `gaelbasta/wiki`** (privé), qui ne contient pas de doc mais la mécanique : `projets.txt` liste les repos publiés ; `scripts/construire.sh` les télécharge **depuis GitHub** (branche `main`) puis construit l'image (MkDocs → nginx `nginxinc/nginx-unprivileged:1.30-alpine`). Copie de travail : `~/claude-projects/wiki`.
  3. **Périmètre par repo** : `md` (tous les `.md` du repo, arborescence conservée — cas normal) ou `tout` (tous les fichiers suivis par Git, pour que les liens vers `scripts/` et les YAML fonctionnent ; utilisé pour prod-01). On prend tout le repo et pas seulement `docs/` car les docs pointent vers des fichiers à la racine (`../../DECISIONS.md`).
  4. **Ordre du menu** : un fichier `.nav.yml` (facultatif) dans chaque dossier du repo du projet ; sans lui, ordre alphabétique des noms de fichiers.
  5. **Image privée** sur GHCR (`ghcr.io/gaelbasta/wiki`, tag daté `AAAA.MM.JJ-HHMM`), déployée avec le chart plateforme en profil `static` sur `https://wiki.prod.gba-lab.win`.
- **Pourquoi** : en production on prend ce qui est stable ; le thème readthedocs est fourni avec MkDocs (une dépendance de moins). La doc publiée est toujours celle qui est **poussée** sur GitHub, jamais une copie locale. L'ordre du menu vit avec la doc qu'il décrit.
- **Conséquences** :
  - Thème readthedocs : pas de mode sombre, pas de bouton « copier », cases à cocher `- [ ]` affichées en texte.
  - Le wiki n'est **pas mis à jour automatiquement** : après un push de doc, reconstruire et redéployer (runbook `wiki.md`). Automatisation possible plus tard.
  - Les dépôts sont téléchargés avec la clé SSH GitHub de dev-linux : la construction se fait sur dev-linux.
  - Sortie de MkDocs 1.x à réévaluer (Zensical stable, ou MkDocs 2.0) : Zensical reprend l'apparence Material, pas readthedocs. Le Markdown, lui, reste identique.
- **Mise en œuvre (2026-10-10)** :
  - Wiki en service sur `https://wiki.prod.gba-lab.win` : image `2026.10.10-1638` (28 Mo), révision Helm 1, chart plateforme 0.1.0. Vérifié : HTTPS valide, 308 → HTTPS, PC et téléphone en Wi-Fi. Runbook : `docs/runbooks/wiki.md`.
  - **Accès du cluster aux images privées GHCR** (premier usage réel, valable pour tous les projets) : **un seul** token GitHub classic `k3s-prod-01-pull`, scope `read:packages`, **sans expiration** (même raisonnement que le token Cloudflare, ADR-022 : une expiration bloquerait un futur déploiement sans prévenir ; risque limité à la lecture des paquets). Rangé dans le gestionnaire de mots de passe ; dans le cluster, un secret `ghcr-pull` **par namespace** qui en a besoin (ADR-008).
  - Docker de dev-linux connecté à GHCR (`docker login ghcr.io`, token `write:packages`), en plus de Helm.

## ADR-025 — Wiki : thème Material et lecture du Markdown « comme VS Code »
- **Date** : 2026-10-10 · **Statut** : Acceptée · **Remplace** : le choix du thème de l'ADR-024 (point 1)
- **Contexte** : en production, le wiki (thème readthedocs) affichait mal certaines pages : blocs de commandes placés dans une liste numérotée aplatis en texte, sous-listes indentées de 2 espaces aplaties (ADR, runbooks). Cause : MkDocs lit le Markdown avec Python-Markdown, **plus strict** que VS Code et GitHub (CommonMark) — ce n'était pas le thème.
- **Décision** :
  1. Thème **Material for MkDocs 9.7.7** (figé) : mode sombre automatique, onglets, bouton « copier » sur les blocs de commandes (utile pour les runbooks).
  2. Extensions de compatibilité, pour que la doc s'écrive comme aujourd'hui dans VS Code : `pymdownx.superfences` (blocs de code dans les listes), `mdx_truly_sane_lists` 1.3 (sous-listes à 2 espaces), `pymdownx.tasklist` (cases à cocher).
- **Pourquoi** : on adapte le wiki à la façon d'écrire, pas l'inverse. Rendu vérifié avant déploiement sur toute la doc de prod-01 (MkDocs 1.6.1 + Material 9.7.7).
- **Conséquences** :
  - Le reste de l'ADR-024 est inchangé (MkDocs 1.6.1 figé, repo `wiki`, périmètres, `.nav.yml`, image privée).
  - Les limites « readthedocs » de l'ADR-024 disparaissent. Le passage futur à Zensical (successeur de Material) se fera sans changement d'apparence.
  - Material affiche à chaque construction un avertissement sur MkDocs 2.0 : informatif, sans effet tant que MkDocs reste figé en 1.6.1.
- **Mise en œuvre (2026-10-10)** : image `2026.10.10-1715`, révision Helm 3 (révision 2 = essai readthedocs `2026.10.10-1700`). Vérifié en local puis en production, PC et téléphone.

## ADR-026 — Le N100 est réinstallé dès la phase 7 (OS + socle), sous le nom `pprod-01`
- **Date** : 2026-10-10 · **Statut** : Acceptée · **Précise** : ADR-014, ADR-012
- **Contexte** : la phase 7 installe le service de sauvegarde sur le N100 (ADR-012), qui doit de toute façon être réinstallé (ADR-014). État constaté le 2026-10-10 : Ubuntu **24.04.2 Desktop**, ancien K3s portant une version de numobserver **abandonnée**, aucune donnée à conserver (décision de Gael, pas de copie). Le disque 3,5" de sauvegarde n'arrivera que le 13 ou le 14 octobre.
- **Décision** :
  1. Réinstaller le N100 **maintenant**, avant l'arrivée du disque : Ubuntu Server 26.04.1 LTS (même clé USB que PROD-01), puis `scripts/socle-os.sh`. **Pas de K3s** à ce stade : la PPROD proprement dite reste en phase 14.
  2. Nom de machine **`pprod-01`** (ex-`gbaubu02p`). IP inchangée `192.168.1.51` (bail statique existant). Clé SSH par poste : `id_ed25519_pprod_01`, alias SSH `pprod-01`.
  3. Partitionnement calqué sur l'ADR-003, adapté au SSD de 512 Go : `/boot/efi` 1 Go, `/boot` 2 Go, LVM `vg0` : `root` 80 Go sur `/`, `rancher` 200 Go sur `/var/lib/rancher` (future PPROD), ~190 Go laissés libres. Le disque de sauvegarde reste **séparé** (ADR-027).
- **Pourquoi** :
  - Le disque de sauvegarde n'est pas branché pendant la réinstallation : **aucun risque de le formater par erreur**, et pas besoin de le débrancher/rebrancher plus tard.
  - Le service de sauvegarde est installé **une seule fois**, sur un système propre, identique à PROD-01.
  - Premier essai réel de `socle-os.sh` sur une autre machine que PROD-01 (objectif initial de la phase 14).
- **Conséquences** :
  - La phase 14 se réduit à : K3s, wildcard `*.pprod.gba-lab.win`, déploiements PPROD.
  - Nouvelle clé d'hôte SSH : effacer l'ancienne empreinte de `192.168.1.51` sur les postes (`ssh-keygen -R`). Les anciens contextes kubectl vers le K3s du N100 deviennent obsolètes.
  - Mode opératoire : [runbook installation-pprod-01.md](docs/runbooks/installation-pprod-01.md).
- **Mise en œuvre (2026-10-10)** : Beelink Mini S (BIOS ADLNV105, non flashé ; seul réglage modifié : *State After G3* → S0, redémarrage après coupure testé). Ubuntu Server 26.04.1 installé, partitionnement conforme, `socle-os.sh` appliqué sans modification. Accès par clé depuis dev-linux et le PC Windows, mots de passe refusés.

## ADR-027 — Sauvegardes : restic sur PROD-01 → rest-server « append-only » sur `pprod-01`
- **Date** : 2026-10-10 · **Statut** : Acceptée (mise en œuvre en phase 7) · **Précise** : ADR-012
- **Décision** :
  1. **Sur `pprod-01` (le coffre)** : le disque 3,5" (ext4, étiquette `sauvegardes`) est monté sur `/srv/sauvegardes` **par son UUID**, avec l'option `nofail` (le N100 démarre même disque débranché). **rest-server** y tourne comme service systemd (hors K3s, ADR-012), sous un utilisateur système dédié, en mode **`--append-only`**, protégé par un identifiant/mot de passe (htpasswd). Pare-feu `ufw` : port de rest-server ouvert **à 192.168.1.16 uniquement**, SSH depuis le LAN.
  2. **Sur PROD-01 (le déposant)** : restic, lancé **chaque nuit** par un timer systemd. Le script (versionné dans `scripts/`) :
     - fait d'abord une **copie cohérente** de la base de K3s (SQLite `state.db`, via la sauvegarde en ligne de SQLite) ;
     - sauvegarde `/etc`, `/var/lib/rancher/k3s/server` (dont le fichier **`token`**, sans lequel la base est inutilisable ; base vivante exclue au profit de la copie), `/var/lib/rancher/k3s/storage` (volumes des apps) ;
     - prévoit un emplacement pour le **dump propre des bases d'apps** (PRISM, phase 8) ;
     - exclut ce qui se retélécharge (images de conteneurs, `/var/lib/rancher/k3s/agent`) ;
     - laisse une trace de la dernière sauvegarde réussie (pour Home Assistant, phase 11).
  3. **Tri des anciennes sauvegardes** (`restic forget --prune`) et **contrôle d'intégrité** (`restic check`) : exécutés **sur `pprod-01`**, directement sur le dossier du dépôt, puisque PROD-01 n'a pas le droit d'effacer. Rétention et horaires fixés à la mise en œuvre.
  4. **Mot de passe restic** : fichier lisible par root seul sur PROD-01 (nécessaire pour sauvegarder) et sur `pprod-01` (pour le tri), **plus une copie obligatoire dans le gestionnaire de mots de passe**. C'est ainsi qu'on lit la phrase de l'ADR-012 « conservé hors de PROD-01 » : sans cette copie, la perte de PROD-01 rendrait les sauvegardes illisibles. Même règle pour l'identifiant rest-server.
- **Pourquoi** :
  - **Append-only** : si PROD-01 est piraté ou si une commande erronée y est tapée, il peut **déposer** mais **jamais effacer** les sauvegardes existantes.
  - *Alternative écartée* : SFTP par SSH vers le N100 — plus simple, mais PROD-01 pourrait tout effacer.
  - restic chiffre **avant** l'envoi : le trafic HTTP sur le LAN ne transporte que des données chiffrées. Seul l'identifiant rest-server circule en clair sur le LAN, et il ne permet que d'ajouter. Limite connue et acceptée (TLS possible plus tard).
- **Contrat avec les apps** (précisé le 2026-10-11, PRISM) : avant l'instantané, le script appelle la commande de copie cohérente de chaque app qui en a une — PRISM : `k3s kubectl -n prism exec deploy/prism -- node src/serveur/sauvegarder.ts` (code 0 = copie écrite et relue dans `/data/sauvegardes`). Code ≠ 0 = sauvegarde notée en échec. Seules les copies de `/data/sauvegardes` sont restaurables, jamais la base vivante (`prism.sqlite`, `-wal`, `-shm`).
- **Validation de la phase 7** : 3 tests de restauration réussis — (1) un fichier de `/etc` restauré et comparé à l'original ; (2) la base K3s restaurée et vérifiée (`PRAGMA integrity_check`) ; (3) un volume de test (chart plateforme) écrit, sauvegardé, supprimé, puis restauré.
- **Conséquences** :
  - Un seul disque = pas de redondance (transitoire, ADR-012) ; migration vers le NAS en phase 16.
  - Mode opératoire : `docs/runbooks/sauvegarde-et-restauration.md` (écrit pendant la phase 7).
  - Mise en œuvre précisée par **ADR-028** (2026-10-13).

## ADR-028 — Coffre `pprod-01` : paquets Ubuntu, rest-server à garde-fou, un sous-dossier par déposant
- **Date** : 2026-10-13 · **Statut** : Acceptée (mise en œuvre en phase 7) · **Précise** : ADR-027
- **Contexte** : versions au 2026-10-13 — rest-server 0.14.0 (dernière officielle, mai 2025) est fourni tel quel par Ubuntu 26.04 (`restic-rest-server` 0.14.0-1, dépôt *universe*) ; restic : 0.18.1 chez Ubuntu (dépôt *main*), 0.19.1 en version officielle (juillet 2026).
- **Décision** :
  1. **restic et rest-server installés par apt** (paquets Ubuntu `restic`, `restic-rest-server`), sur PROD-01 comme sur `pprod-01`. Pas de binaire téléchargé à la main.
  2. **Un script versionné** `scripts/coffre-sauvegardes.sh`, en sous-commandes lancées une par une (`pare-feu`, `rest-server`, puis `disque`).
  3. **rest-server** : notre propre service systemd (`/etc/systemd/system/rest-server.service` ; le service du paquet, `restic-rest-server.service`, est arrêté et désactivé ; la commande s'appelle `/usr/bin/restic-rest-server`), utilisateur système `restic` sans connexion, port **8000**, options `--append-only --private-repos`. Durcissement systemd : écriture autorisée uniquement dans le dépôt.
  4. **Garde-fou disque** : le service ne démarre **que si `/srv/sauvegardes` est un point de montage** (`ConditionPathIsMountPoint`). Disque absent (option `nofail`) = pas de rest-server = sauvegarde de la nuit en échec, visible.
  5. **Un identifiant par déposant**, qui est aussi son sous-dossier (`--private-repos`) : PROD-01 = `prod-01` → dépôt `rest:http://192.168.1.51:8000/prod-01/`. Mot de passe haché (bcrypt) dans `/etc/rest-server/.htpasswd` (root:restic, 640) ; en clair seulement dans le gestionnaire de mots de passe et, plus tard, sur PROD-01.
  6. **Pare-feu `pprod-01`** : tout refusé en entrée sauf SSH depuis `192.168.1.0/24` et le port 8000 depuis `192.168.1.16` uniquement. Les règles K3s de la phase 14 (`install-k3s.sh`) s'ajouteront sans conflit.
  7. **Disque** (précisé le 2026-10-14) : Seagate IronWolf ST4000VN006 4 To, n° **WW6AR4CY**, boîtier USB CENMATE 2 baies (puce ASMedia, UAS), baie 1. Tests SMART court et long réussis avant tout formatage. La sous-commande `disque` le reconnaît **par son n° de série SMART** (jamais par son nom `/dev/sdX`, qui peut changer), refuse de toucher un disque système ou un disque non vierge, et demande de taper `EFFACER`. Table GPT, une partition, ext4 étiquette `sauvegardes`, `-m 0` (pas de réserve root, inutile hors système : +200 Go), `-T largefile` (1 inode par Mo : restic écrit peu de gros fichiers). Montage `/srv/sauvegardes` par UUID, options `noatime,nofail,x-systemd.device-timeout=15s`. Le dossier `/srv/sauvegardes` vide est rendu **immuable** (`chattr +i`) : disque absent, plus rien ne peut y écrire (second garde-fou après le point 4).
- **Pourquoi** :
  - *Point 1* : paquets signés par Ubuntu, même version sur les deux machines, mises à jour avec le système. restic 0.18.1 suffit (format de dépôt identique) ; passer à la 0.19 n'apporterait rien d'utile ici.
  - *Point 4* : sans ce garde-fou, un disque débranché ferait écrire les sauvegardes **dans le dossier vide du SSD système**, en silence, jusqu'à le remplir.
  - *Point 5* : un futur déposant (PPROD, phase 14) aura son propre identifiant et son propre dossier, sans pouvoir lire les sauvegardes de PROD-01.
- **Conséquences** :
  - Les dépôts Ubuntu peuvent garder la 0.18 longtemps ; à réévaluer si une fonction de restic 0.19+ devient nécessaire.
  - `apache2-utils` installé sur `pprod-01` (commande `htpasswd`).

## ADR-029 — Sauvegarde nocturne de PROD-01 : script unique, 3 h, échec partiel = échec
- **Date** : 2026-10-13 · **Statut** : Acceptée (mise en œuvre en phase 7) · **Précise** : ADR-027, ADR-028
- **Décision** :
  1. **Un script versionné** `scripts/sauvegarde-prod-01.sh`, copié sur PROD-01 dans `/usr/local/sbin/sauvegarde-prod-01`, en sous-commandes : `installer`, `initialiser` (création du dépôt, une fois), `lancer` (une sauvegarde), `activer` (timer).
  2. **Chaque nuit à 3 h** (timer systemd, `Persistent=true` : machine éteinte à 3 h → sauvegarde au démarrage suivant), en priorité basse (CPU et disque).
  3. **Ordre** : copies cohérentes des apps (PRISM) → copie de la base K3s (`sqlite3 .backup` + `PRAGMA integrity_check`) → `restic backup` de `/etc`, `/var/lib/rancher/k3s/server`, `/var/lib/rancher/k3s/storage` et des copies (`/var/lib/sauvegarde-prod-01`). Exclus : bases vivantes (K3s `state.db*`, PRISM `prism.sqlite*`), `kine.sock`, et `/var/lib/rancher/k3s/agent` (images, ~1,6 Go, se retéléchargent).
  4. **Une étape en échec n'arrête pas les suivantes**, mais la sauvegarde est notée **en échec** (code ≠ 0, fichier `derniere-tentative`). `derniere-reussite` n'est écrit que si tout a réussi.
  5. **Secrets sur PROD-01** dans `/etc/restic/` (root, 600) : `motdepasse` (restic) et `prod-01.env` (dépôt + identifiant rest-server). Saisis à l'installation, jamais dans Git ; originaux dans le gestionnaire de mots de passe (« restic – dépôt prod-01 », « rest-server pprod-01 – prod-01 »).
- **Pourquoi** : une sauvegarde partielle vaut mieux que rien, mais ne doit jamais passer pour complète. 3 h : personne n'utilise PRISM. Volume constaté le 2026-10-13 : ~45 Mo (`/etc` 6,5 Mo, `server` 35 Mo, `storage` 1,3 Mo).
- **Conséquences** : Home Assistant (phase 11) surveillera `/var/lib/sauvegarde-prod-01/derniere-reussite` (alerte au-delà de 26 h). Le timer n'est activé qu'après une première sauvegarde manuelle réussie.

## ADR-015 — Onduleur
- **Date** : 2026-10-09 · **Statut** : Ouverte
- **Contexte** : onduleur existant (HA, N100, bientôt PROD-01), relié à aucune machine aujourd'hui.
- **À décider** : modèle et port USB ; quelle machine pilote l'arrêt propre (NUT).
