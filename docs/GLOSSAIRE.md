# Glossaire

Chaque terme : **ce que c'est**, puis **une image** pour s'en souvenir.

| Terme | Ce que c'est | Image |
|---|---|---|
| **ADR** | Une décision d'architecture écrite, avec son pourquoi (voir `DECISIONS.md`). | Le procès-verbal d'une réunion avec soi-même. |
| **Argo CD** | Outil qui compare le repo Git au cluster et corrige les différences tout seul. | Un régisseur qui remet le décor conforme au plan. |
| **cert-manager** | Outil qui obtient et renouvelle automatiquement les certificats HTTPS. | Un secrétaire qui renouvelle ton passeport avant expiration. |
| **Certificat wildcard** | Un certificat HTTPS valable pour tous les sous-noms (`*.prod.<domaine>`). | Un passe-partout pour toutes les portes d'un étage. |
| **Conteneur** | Une application emballée avec tout ce dont elle a besoin pour tourner. | Un plat sous vide : on le réchauffe n'importe où, il a le même goût. |
| **DNS** | Le service qui traduit un nom (`prism.prod…`) en adresse IP. | L'annuaire téléphonique. |
| **DNS rebinding (protection)** | Sécurité de certaines box qui refuse qu'un nom public pointe vers une IP de la maison. | Un standardiste méfiant. |
| **GHCR** | GitHub Container Registry : l'entrepôt où sont rangées les images de mes apps. | Le congélateur où sont stockés les plats sous vide. |
| **Image** | Le modèle figé d'un conteneur, versionné (`prism:1.4.0`). | La recette + le plat congelé, avec une étiquette de version. |
| **Ingress** | La règle qui dit à Traefik « tel nom → telle app ». | Un panneau indicateur. |
| **K3s** | Une distribution légère de Kubernetes. | Kubernetes en format mini-PC. |
| **kubectl** | L'outil en ligne de commande pour parler au cluster. | La télécommande. |
| **k9s** | Une interface texte pour voir et piloter le cluster. | Le tableau de bord de la voiture. |
| **Kubernetes** | Le système qui lance les conteneurs, les relance s'ils tombent et les relie entre eux. | Un chef d'orchestre. |
| **kustomize / overlay** | Une base commune + de petites différences par environnement (pprod, prod). | Un même costume avec des retouches différentes. |
| **LVM** | Une couche qui découpe le disque en volumes redimensionnables. | Des cloisons amovibles au lieu de murs porteurs. |
| **Manifeste** | Un fichier YAML qui décrit ce qu'on veut dans le cluster. | Une commande passée au restaurant. |
| **Namespace** | Un compartiment du cluster ; un par projet. | Un tiroir par projet. |
| **NUT** | Logiciel qui lit l'état de l'onduleur et éteint proprement les machines. | Le gardien qui ferme la boutique avant la coupure. |
| **Pod** | La plus petite unité qui tourne dans Kubernetes (1 ou plusieurs conteneurs). | Une assiette servie. |
| **PPROD** | Préproduction : copie de la prod pour tester avant. | La répétition générale. |
| **PVC / volume** | L'espace disque réservé à une app pour ses données. | Le casier personnel d'une app. |
| **PWA** | Un site web installable comme une app sur téléphone. Exige HTTPS. | Un raccourci qui se prend pour une vraie app. |
| **restic** | Outil de sauvegarde chiffrée et dédupliquée. | Un coffre-fort qui ne stocke qu'une fois ce qui ne change pas. |
| **Runbook** | Une procédure pas-à-pas pour une opération (dans `docs/runbooks/`). | Une fiche recette. |
| **Sealed Secrets** | Secrets chiffrés qu'on peut ranger dans Git sans risque. | Une lettre sous enveloppe scellée que seul PROD-01 sait ouvrir. |
| **SSH par clé** | Connexion à distance sans mot de passe, avec une paire de clés. | Une clé physique plutôt qu'un code à 4 chiffres. |
| **Tailscale** | Un réseau privé chiffré entre mes appareils, où qu'ils soient. | Un couloir secret entre ta poche et la maison. |
| **Traefik** | Le point d'entrée HTTP(S) du cluster. | Le portier qui oriente les visiteurs. |
