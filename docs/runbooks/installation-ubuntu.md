# Phase 2 — Installation d'Ubuntu Server

**Quoi** : installer Ubuntu Server 26.04.1 LTS sur le NVMe de PROD-01, avec le partitionnement de l'ADR-003.
**Réalisé le** : 2026-10-09 · **Durée** : ~45 min
**Risque** : efface tout le contenu du NVMe (Windows compris).

## Prérequis

- BIOS réglé (voir [phase-0-1-preparation-bios.md](phase-0-1-preparation-bios.md)).
- Clé USB Ubuntu Server 26.04.1 LTS (Rufus).
- Écran HDMI + clavier, câble réseau dans le **port RJ45 de gauche** (`enp3s0`).

## Comment

### 1. Démarrage
Clé branchée, allumer : l'USB est en tête de l'ordre de démarrage (sinon **F7**). Choisir *Try or Install Ubuntu Server*.

### 2. Premiers écrans
| Écran | Choix |
|---|---|
| Langue | English |
| Mise à jour de l'installeur | Update to the new installer |
| Clavier | Layout `French`, Variant `French` |
| Type | Ubuntu Server (pas *minimized*), sans pilotes tiers |
| Réseau | DHCP automatique sur `enp3s0` (ne rien modifier) |
| Proxy / Mirror | vide / par défaut |
| Paquets Wi-Fi | ne pas installer |

### 3. Stockage — *Custom storage layout*
Navigation : flèches, **Entrée** = menu d'une ligne, **Tab** = champ suivant, **Reset** = tout recommencer. Rien n'est écrit avant la confirmation finale.

1. Ligne du disque `EXT X200E SSD` → **Reformat**. **Ne jamais toucher la ligne de la clé USB.**
2. Ligne du disque → **Use As Boot Device** (crée `/boot/efi`, 1 Go).
3. `free space` → **Add GPT Partition** : `2G`, ext4, `/boot`.
4. `free space` → **Add GPT Partition** : taille vide, **Leave unformatted**.
5. **Create volume group (LVM)** : nom `vg0`, cocher la partition de l'étape 4, sans chiffrement.
6. `vg0` › `free space` → **Create Logical Volume** : `root`, `80G`, ext4, `/`.
7. `vg0` › `free space` → **Create Logical Volume** : `rancher`, `350G`, ext4, Other → `/var/lib/rancher`.
8. Vérifier le *FILE SYSTEM SUMMARY* (4 lignes) et ~520 Go libres dans `vg0`, puis **Done → Continue**.

### 4. Profil et fin
| Écran | Choix |
|---|---|
| Your name / Server's name / Username | `Gael` / `prod-01` / `gael` |
| Mot de passe | rangé dans le gestionnaire de mots de passe (entrée « PROD-01 – gael ») |
| Ubuntu Pro | Skip for now |
| SSH | Install OpenSSH server ; aucune clé importée ; mot de passe autorisé (temporaire, retiré en phase 3) |
| Featured snaps | aucun |

Reboot Now, retirer la clé quand demandé.

## Vérifier

Commandes à lancer après connexion : `ip -br a`, `lsblk`, `free -h`, `df -h`.

Résultat obtenu le 2026-10-09 :

| Contrôle | Attendu | Obtenu |
|---|---|---|
| Réseau | `enp3s0` UP avec une IP | ✅ `192.168.1.16/24` (DHCP, provisoire) + IPv6 ; `eno1` et `wlp4s0` DOWN |
| Disque | 953,9 Go | ✅ `nvme0n1` |
| `/boot/efi` · `/boot` | 1 Go · 2 Go | ✅ |
| `/` | 80 Go | ✅ `vg0-root` (79 Go utiles) |
| `/var/lib/rancher` | 350 Go | ✅ `vg0-rancher` (344 Go utiles) |
| RAM visible | ~29 Go (UMA à 512 Mo) | ✅ 29 Gi total, 28 Gi disponibles |
| Swap | — | ⚠️ 8 Gi (fichier `/swap.img` créé par l'installeur) → traité en phase 3 |

## Revenir en arrière

Réinstaller depuis la clé USB en suivant cette même fiche. Aucune donnée à préserver à ce stade.
