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

## ADR-020 — Pare-feu de l'hôte reporté à la phase 4
- **Date** : 2026-10-10 · **Statut** : Proposée
- **Décision** : le pare-feu (ufw) sera activé avec K3s, en ouvrant SSH, HTTP/HTTPS, l'API Kubernetes et les réseaux internes de K3s.
- **Pourquoi** : un pare-feu activé avant K3s sans ses règles bloque le réseau interne des pods. Le serveur n'est de toute façon pas exposé à Internet (aucun port ouvert sur la Livebox, pare-feu IPv6 de la box actif).

## ADR-015 — Onduleur
- **Date** : 2026-10-09 · **Statut** : Ouverte
- **Contexte** : onduleur existant (HA, N100, bientôt PROD-01), relié à aucune machine aujourd'hui.
- **À décider** : modèle et port USB ; quelle machine pilote l'arrêt propre (NUT).
