# Phase 7 — Réinstallation du N100 en `pprod-01` (Ubuntu Server + socle)

**Quoi** : réinstaller le mini-PC N100 (ex-`gbaubu02p`) en Ubuntu Server 26.04.1 LTS, le nommer `pprod-01` et lui appliquer le socle de PROD-01 (`scripts/socle-os.sh`). Pas de K3s à ce stade (ADR-026).
**Réalisé le** : 🟨 *à compléter* · **Durée** : *à compléter*
**Risque** : efface tout le SSD du N100 (Ubuntu 24.04 Desktop, ancien K3s, numobserver abandonné — rien à conserver, décision du 2026-10-10).

> Fiche **préparée avant l'opération**. Les cases ❓ et les résultats seront complétés avec ce qui a réellement été fait.

## Prérequis

- Clé USB Ubuntu Server 26.04.1 LTS (la même que pour PROD-01).
- Écran HDMI + clavier sur le N100, câble réseau branché.
- **Disque 3,5" de sauvegarde NON branché** (il sera ajouté ensuite, ADR-027).
- Une nouvelle entrée « PPROD-01 – gael » prête dans le gestionnaire de mots de passe.

## Comment

### 1. Arrêter l'ancien système
Depuis le N100 (invite `gael@gbaubu02p`) : `sudo poweroff`.

### 2. Démarrer sur la clé USB
Clé branchée, allumer en tapant la touche du menu de démarrage (❓ *touche réelle à noter : F7, F11, F12 ou Échap selon le fabricant*). Choisir *Try or Install Ubuntu Server*.

### 3. Premiers écrans
Identiques à PROD-01 ([installation-ubuntu.md](installation-ubuntu.md) §2) : English, nouvel installeur, clavier `French`/`French`, Ubuntu Server (pas *minimized*), DHCP sur la carte réseau câblée (❓ *nom de l'interface à noter*), proxy vide, mirror par défaut.

### 4. Stockage — *Custom storage layout* (ADR-026)
Rien n'est écrit avant la confirmation finale.

1. Ligne du disque **`512GB SSD`** → **Reformat**. **Ne jamais toucher la ligne de la clé USB.**
2. Ligne du disque → **Use As Boot Device** (crée `/boot/efi`, 1 Go).
3. `free space` → **Add GPT Partition** : `2G`, ext4, `/boot`.
4. `free space` → **Add GPT Partition** : taille vide, **Leave unformatted**.
5. **Create volume group (LVM)** : nom `vg0`, cocher la partition de l'étape 4, sans chiffrement.
6. `vg0` › `free space` → **Create Logical Volume** : `root`, `80G`, ext4, `/`.
7. `vg0` › `free space` → **Create Logical Volume** : `rancher`, `200G`, ext4, Other → `/var/lib/rancher`.
8. Vérifier le *FILE SYSTEM SUMMARY* (4 lignes) et ~190 Go libres dans `vg0`, puis **Done → Continue**.

### 5. Profil et fin
| Écran | Choix |
|---|---|
| Your name / Server's name / Username | `Gael` / `pprod-01` / `gael` |
| Mot de passe | rangé dans le gestionnaire de mots de passe (entrée « PPROD-01 – gael ») |
| Ubuntu Pro | Skip for now |
| SSH | Install OpenSSH server ; aucune clé importée ; mot de passe autorisé (temporaire, retiré par le socle) |
| Featured snaps | aucun |

Reboot Now, retirer la clé quand demandé. Noter l'empreinte de la clé d'hôte, en console : `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` (❓ *à reporter ci-dessous*).

### 6. Livebox
Le bail statique `E8:FF:1E:D4:F6:07` → `192.168.1.51` existe déjà : le garder, le renommer `pprod-01` si la Livebox l'accepte.

### 7. Clés SSH des postes (convention `id_ed25519_<destination>`)

L'ancienne empreinte de `192.168.1.51` doit d'abord être oubliée (sinon SSH refuse, à raison : la machine a changé).

**dev-linux**
```bash
ssh-keygen -R 192.168.1.51
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_pprod_01 -C "gael@dev-linux vers pprod-01"
ssh-copy-id -i ~/.ssh/id_ed25519_pprod_01.pub gael@192.168.1.51
cat >> ~/.ssh/config <<'EOF'

Host pprod-01
    HostName 192.168.1.51
    User gael
    IdentityFile ~/.ssh/id_ed25519_pprod_01
    IdentitiesOnly yes
EOF
```

**PC Windows (PowerShell)**
```powershell
ssh-keygen -R 192.168.1.51
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519_pprod_01 -C "gael@pc-windows vers pprod-01"
Get-Content $env:USERPROFILE\.ssh\id_ed25519_pprod_01.pub | ssh gael@192.168.1.51 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
notepad $env:USERPROFILE\.ssh\config   # ajouter le bloc Host pprod-01 ci-dessus
```

| Poste | Clé | Empreinte |
|---|---|---|
| PC Windows | `C:\Users\diyod\.ssh\id_ed25519_pprod_01` | ❓ |
| dev-linux | `~/.ssh/id_ed25519_pprod_01` | ❓ |

Empreinte **du serveur** `pprod-01` (ED25519) : ❓

### 8. Socle OS
Tester d'abord `ssh pprod-01 hostname` depuis **les deux** postes (le script refuse de tourner sans clé autorisée, mais il ne sait pas si elle fonctionne). Puis, depuis dev-linux :
```bash
scp ~/claude-projects/prod-01/scripts/socle-os.sh pprod-01:
ssh pprod-01
sudo bash ~/socle-os.sh
```
**Garder cette session ouverte** et tester `ssh pprod-01 hostname` depuis une nouvelle fenêtre avant de la fermer. Puis `sudo reboot`.

### 9. Nettoyage des postes
Les anciens contextes kubectl vers le K3s du N100 sont obsolètes : `kubectl config get-contexts`, puis `kubectl config delete-context <nom>` (❓ *noms réels à noter*).

## Vérifier (après redémarrage)

Mêmes contrôles que PROD-01 ([socle-os.md](socle-os.md)) :
```bash
hostname; date
ip -br a
lsblk
timedatectl | grep -E 'Time zone|synchronized'
swapon --show
rfkill list | grep -i soft
sudo sshd -T | grep -Ei '^(passwordauthentication|permitrootlogin)'
```

| Contrôle | Attendu | Obtenu |
|---|---|---|
| Nom | `pprod-01` | ❓ |
| Réseau | `192.168.1.51/24` | ❓ |
| `/` · `/var/lib/rancher` | 80 Go · 200 Go, ~190 Go libres dans `vg0` | ❓ |
| Fuseau | Europe/Paris, synchronisé | ❓ |
| Swap | aucun | ❓ |
| SSH | clés uniquement, root refusé | ❓ |

## Revenir en arrière

Réinstaller depuis la clé USB en suivant cette même fiche. Aucune donnée à préserver à ce stade (le disque de sauvegarde n'est pas encore branché). Accès de secours : écran + clavier, `gael` + mot de passe.
