# Glossaire

Chaque terme : **ce que c'est**, puis **une image** pour s'en souvenir.

| Terme | Ce que c'est | Image |
|---|---|---|
| **ADR** | Une décision d'architecture écrite, avec son pourquoi (voir `DECISIONS.md`). | Le procès-verbal d'une réunion avec soi-même. |
| **Argo CD** | Outil qui compare le repo Git au cluster et corrige les différences tout seul. | Un régisseur qui remet le décor conforme au plan. |
| **awesome-nav (`.nav.yml`)** | Plugin MkDocs : un petit fichier `.nav.yml` dans un dossier fixe l'ordre et les titres du menu du wiki. | Le plan de table d'un mariage. |
| **cert-manager** | Outil qui obtient et renouvelle automatiquement les certificats HTTPS. | Un secrétaire qui renouvelle ton passeport avant expiration. |
| **Certificat wildcard** | Un certificat HTTPS valable pour tous les sous-noms (`*.prod.<domaine>`). | Un passe-partout pour toutes les portes d'un étage. |
| **Chart Helm** | Un paquet d'installation pour Kubernetes : des modèles + des valeurs par défaut. Le « chart plateforme » est le nôtre, commun à tous les projets. | Un moule à gâteau : on change la garniture (les valeurs), pas le moule. |
| **ClusterIssuer** | La fiche qui dit à cert-manager à qui demander les certificats et comment prouver le domaine. Ici : `letsencrypt-staging` et `letsencrypt-prod`. | Le guichet de la préfecture. |
| **Conteneur** | Une application emballée avec tout ce dont elle a besoin pour tourner. | Un plat sous vide : on le réchauffe n'importe où, il a le même goût. |
| **DNS rebinding (protection)** | Sécurité de certaines box qui refuse qu'un nom public pointe vers une IP de la maison. | Un standardiste méfiant. |
| **DNS** | Le service qui traduit un nom (`prism.prod…`) en adresse IP. | L'annuaire téléphonique. |
| **DNS-01 (validation)** | Preuve de propriété du domaine par un enregistrement TXT temporaire dans le DNS ; fonctionne sans exposer le serveur à Internet. | Prouver qu'une maison est à toi en écrivant un code sur la boîte aux lettres. |
| **GHCR** | GitHub Container Registry : l'entrepôt où sont rangées les images de mes apps. | Le congélateur où sont stockés les plats sous vide. |
| **Helm** | L'outil qui installe, met à jour et revient en arrière sur des charts (`helm upgrade --install`, `helm rollback`). | Le livreur-installateur qui garde le bon de livraison de chaque version. |
| **HelmChartConfig** | Fichier de surcharge K3s pour régler une appli que K3s installe lui-même (ici Traefik), sans toucher à son installation. | Un post-it collé sur la notice de montage. |
| **Image** | Le modèle figé d'un conteneur, versionné (`prism:1.4.0`). | La recette + le plat congelé, avec une étiquette de version. |
| **imagePullSecret (`ghcr-pull`)** | Secret qui permet au cluster de télécharger une image **privée** depuis GHCR ; un par namespace. | Le badge d'accès à l'entrepôt. |
| **Ingress** | La règle qui dit à Traefik « tel nom → telle app ». | Un panneau indicateur. |
| **K3s** | Une distribution légère de Kubernetes. | Kubernetes en format mini-PC. |
| **k9s** | Une interface texte pour voir et piloter le cluster. | Le tableau de bord de la voiture. |
| **kubectl** | L'outil en ligne de commande pour parler au cluster. | La télécommande. |
| **Kubernetes** | Le système qui lance les conteneurs, les relance s'ils tombent et les relie entre eux. | Un chef d'orchestre. |
| **kustomize / overlay** | Une base commune + de petites différences par environnement (pprod, prod). | Un même costume avec des retouches différentes. |
| **Let's Encrypt (staging / production)** | Autorité gratuite qui délivre les certificats HTTPS. Le staging est un bac à sable (certificats non reconnus, quotas larges) pour tester sans risque. | La répétition avant l'examen officiel. |
| **LVM** | Une couche qui découpe le disque en volumes redimensionnables. | Des cloisons amovibles au lieu de murs porteurs. |
| **Manifeste** | Un fichier YAML qui décrit ce qu'on veut dans le cluster. | Une commande passée au restaurant. |
| **MkDocs** | Outil qui transforme des fichiers Markdown en site web de documentation (ici avec le thème Material). | Un imprimeur qui relie tes fiches en un livre. |
| **Namespace** | Un compartiment du cluster ; un par projet. | Un tiroir par projet. |
| **NUT** | Logiciel qui lit l'état de l'onduleur et éteint proprement les machines. | Le gardien qui ferme la boutique avant la coupure. |
| **Paquet OCI / registre** | Format « image de conteneur » utilisé aussi pour ranger des charts Helm dans GHCR (`oci://ghcr.io/…`). | Le même entrepôt pour les plats et les moules. |
| **Pod** | La plus petite unité qui tourne dans Kubernetes (1 ou plusieurs conteneurs). | Une assiette servie. |
| **PPROD** | Préproduction : copie de la prod pour tester avant. | La répétition générale. |
| **preStop (pause d'arrêt)** | Petite attente avant l'arrêt d'un pod, le temps que Traefik ne lui envoie plus de requêtes : mises à jour sans coupure. | Finir de servir la table avant de quitter son service. |
| **PVC / volume** | L'espace disque réservé à une app pour ses données. | Le casier personnel d'une app. |
| **PWA** | Un site web installable comme une app sur téléphone. Exige HTTPS. | Un raccourci qui se prend pour une vraie app. |
| **Redirection 308** | Réponse « cette page est définitivement à cette autre adresse » : ici tout `http://` vers `https://`. | Un panneau « entrée par l'autre porte ». |
| **restic** | Outil de sauvegarde chiffrée et dédupliquée. | Un coffre-fort qui ne stocke qu'une fois ce qui ne change pas. |
| **Rollback** | Retour à une version précédente d'un déploiement Helm (`helm rollback`) ; ajoute une ligne à l'historique, n'efface rien. | La touche « annuler », avec trace. |
| **Runbook** | Une procédure pas-à-pas pour une opération (dans `docs/runbooks/`). | Une fiche recette. |
| **Sealed Secrets** | Secrets chiffrés qu'on peut ranger dans Git sans risque. | Une lettre sous enveloppe scellée que seul PROD-01 sait ouvrir. |
| **Secret** | Objet Kubernetes qui contient une donnée sensible (token, mot de passe). Sa valeur n'est jamais dans Git, seul son emplacement est documenté. | Un coffre dont on note l'adresse, pas la combinaison. |
| **SSH par clé** | Connexion à distance sans mot de passe, avec une paire de clés. | Une clé physique plutôt qu'un code à 4 chiffres. |
| **Tag Git** | Marque-page posé sur un commit (ex. `plateforme-0.1.0`) pour retrouver exactement le code d'une version publiée. | Un signet dans un livre. |
| **Tailscale** | Un réseau privé chiffré entre mes appareils, où qu'ils soient. | Un couloir secret entre ta poche et la maison. |
| **TLSStore** | Objet Traefik qui définit le certificat présenté par défaut. Le nôtre (`kube-system/default`) pointe vers le wildcard. | Le badge que le portier montre à tous les visiteurs. |
| **Traefik** | Le point d'entrée HTTP(S) du cluster. | Le portier qui oriente les visiteurs. |
