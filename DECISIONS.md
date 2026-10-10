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

## ADR-012 — Sauvegardes
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : restic (chiffré) depuis PROD-01 vers le disque 3,5" branché sur le **N100**, en attendant le NAS. Le service de sauvegarde tourne sur le système du N100, hors K3s.
- **Contenu** : données des apps (avec dump propre des bases), base de K3s, `/etc`, clés de secrets.
- **Pourquoi** : une sauvegarde sur une autre machine survit à la perte de PROD-01.
- **Conséquences** : un seul disque = pas de redondance (transitoire). Une sauvegarde n'est validée qu'après un **test de restauration**. Le mot de passe restic est conservé hors de PROD-01.

## ADR-013 — Surveillance par Home Assistant
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : HA surveille PROD-01 depuis l'extérieur : ping, check HTTP de chaque app, métriques de l'hôte. Alerte prioritaire : **absence de données**.
- **Pourquoi** : HA existe déjà et est une machine distincte de PROD-01.

## ADR-014 — Le N100 devient la PPROD
- **Date** : 2026-10-09 · **Statut** : Acceptée
- **Décision** : le N100 est réinstallé (ISO propre) après PROD-01 et devient la PPROD.
- **Conditions** : identique à la PROD par construction (mêmes scripts, mêmes manifestes, overlays `pprod`/`prod`) ; **aucune donnée réelle** (PRISM avec données de test).
- **Conséquences** : la réinstallation du N100 sert de premier test de reconstruction. Le disque de sauvegarde devra être remonté après la réinstallation.

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
  - Redirection automatique HTTP → HTTPS : pas encore en place (à traiter avec le chart plateforme).

## ADR-015 — Onduleur
- **Date** : 2026-10-09 · **Statut** : Ouverte
- **Contexte** : onduleur existant (HA, N100, bientôt PROD-01), relié à aucune machine aujourd'hui.
- **À décider** : modèle et port USB ; quelle machine pilote l'arrêt propre (NUT).
