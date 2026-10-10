# Phase 0–1 — Préparation et BIOS

**Quoi** : préparer l'installation et régler le BIOS avant d'effacer Windows.
**Durée estimée** : 1 h, hors achat du domaine.
**Risque** : nul tant qu'on ne flashe pas le BIOS. Le flash se décide ensemble.

## Étape 1 — Premier démarrage : directement dans le BIOS (pas de Windows)

> Décision du 2026-10-09 : on **ne configure pas Windows 11**. Il n'est utile que si la mise à jour du BIOS exige un outil Windows, ce qu'on saura après l'étape 2.

1. Brancher écran (HDMI), clavier, câble réseau.
2. Allumer et appuyer plusieurs fois sur **Suppr** (ou **F7**) dès l'allumage.
3. Si Windows démarre quand même (écran « Choisissez votre pays ») : **éteindre** par un appui long sur le bouton, et recommencer en tapant plus tôt.

## Étape 2 — Photographier le BIOS

1. Photographier : la page d'accueil (**version du BIOS** et date), puis chaque onglet (**Advanced**, **Power** / **Chipset**, **Boot**, **Security**).
2. Ne rien modifier pour l'instant. Quitter avec **« Discard changes and exit »**.
3. Claude compare la version avec le [centre de téléchargement GMKtec](https://gmktec.fr/pages/download-center) et indique la méthode de mise à jour. **Ne rien flasher seul.**

### Cas particulier : la mise à jour exige Windows

Faire une configuration Windows **minimale et hors ligne** : câble réseau débranché, compte local, aucune option, aucun compte Microsoft. Windows sera effacé juste après ; la licence reste enregistrée dans le firmware.

Réglages qu'on cherchera ensemble :

| Réglage | Valeur cible | Pourquoi |
|---|---|---|
| Restore on AC Power Loss | Power On | Redémarre seul après une coupure |
| Wi-Fi / Bluetooth | Disabled | Inutiles sur un serveur |
| Secure Boot | à voir ensemble | Compatible Ubuntu, mais à vérifier |
| Ventilation | profil équilibré | Bruit / température |

## Constats du 2026-10-09 (premier démarrage)

| Élément | Valeur relevée | Commentaire |
|---|---|---|
| BIOS | AMI Aptio, NucBox K8 Plus **1.02** du 22/08/2025 | Aucune mise à jour publiée sur le centre de téléchargement GMKtec FR → pas de flash, Windows inutile |
| CPU | Ryzen 7 8845HS, 3,8 GHz | OK |
| RAM | 32 768 Mo DDR5 5600 | OK |
| SSD | « EXT X200E SSD » (marque à identifier en phase 1 via SMART) | Contient encore Windows |
| Power Mode | Balance | Conservé (à revoir après test thermique) |
| Mots de passe BIOS | aucun | — |
| Numéro de série | « Default string » | Normal chez GMKtec ; ne pas s'en servir pour identifier la machine |
| Slots NVMe | SSD0 = EXT X200E, **SSD1 = libre** | Second slot disponible pour un futur disque |
| Mémoire vidéo (UMA) | 3 Go | Réduite à 512 Mo (serveur sans écran) |
| Températures au repos | CPU 33 °C, ventilateurs 850 / 1 614 tr/min, mode Auto | OK ; courbe de ventilation d'usine conservée |
| Secure Boot | Disabled, mode Standard | Conservé désactivé (ADR-016) |
| Wi-Fi / Bluetooth | Aucune option dans le BIOS | Désactivés côté Linux en phase 3 |
| Démarrage réseau | Pas d'option « Disabled » | Laissé en dernière position, sans effet tant que le NVMe démarre |
| Date système | 10/10/2026 alors qu'on est le 09/10 | Horloge corrigée automatiquement par Linux (NTP) |

Réglages à appliquer (voir étape 2 bis).

## Étape 2 bis — Réglages BIOS retenus

| Menu | Réglage | Avant | Après | Pourquoi |
|---|---|---|---|---|
| Advanced | Auto Power On | Power Off | **Power On** | Redémarre seul après une coupure de courant |
| Advanced | Wake On LAN | Enabled | Enabled | Permet de réveiller PROD-01 à distance (HA) |
| Boot | Boot Option #5 | Network | Network (inchangé) | Pas d'option « Disabled » ; position 5 = jamais atteinte |
| Advanced › GFX Configuration | UMA Frame buffer Size | 3G | **512M** | Rend ~2,5 Go de RAM au serveur |
| Security › Secure Boot | Secure Boot | Disabled | Disabled | Voir ADR-016 |
| Boot | Ordre | USB puis NVMe | inchangé pour l'installation ; **NVMe en 1er** après | Évite de relancer l'installeur si une clé reste branchée |

## Étape 3 — Préparer la clé USB d'installation

1. Télécharger l'ISO **Ubuntu Server 26.04.1 LTS** sur ubuntu.com.
2. Utiliser **Rufus** (Windows) : sélectionner la clé, l'ISO, laisser les options par défaut, Démarrer.
3. Clé ≥ 4 Go — **son contenu sera effacé**.

## Étape 4 — Choisir et réserver le nom de domaine

- Registrar conseillé : **Cloudflare** (prix coûtant, compatible nativement avec cert-manager) ou **OVH** (français).
- Choisir un nom court et neutre, pas forcément lié à un projet.
- Ne rien configurer d'autre pour l'instant.

## Vérifier

- [ ] Photo de la version du BIOS envoyée
- [ ] Photos des onglets du BIOS envoyées
- [ ] Clé USB Ubuntu prête
- [ ] Domaine réservé (nom noté dans ADR-009)

## Revenir en arrière

Rien à annuler : aucune modification n'est faite à cette étape.
