# Phase 7 — Réinstallation du N100 en `pprod-01` (BIOS, Ubuntu Server, socle)

**Quoi** : régler le BIOS du mini-PC N100 (ex-`gbaubu02p`), le réinstaller en Ubuntu Server 26.04.1 LTS sous le nom `pprod-01` et lui appliquer le socle de PROD-01 (`scripts/socle-os.sh`). Pas de K3s à ce stade (ADR-026).
**Réalisé le** : 2026-10-10, de 22 h 40 à 0 h 10 (~1 h 30, BIOS compris)
**Risque** : efface tout le SSD du N100 (Ubuntu 24.04 Desktop, ancien K3s, numobserver abandonné — rien conservé, décision du 2026-10-10).

## Prérequis

- Clé USB Ubuntu Server 26.04.1 LTS (la même que pour PROD-01).
- Écran HDMI + clavier sur le N100, câble réseau branché.
- **Disque 3,5" de sauvegarde NON branché** (il sera ajouté ensuite, ADR-027).
- Une entrée « PPROD-01 – gael » prête dans le gestionnaire de mots de passe.

## 1. Identifier la machine (avant d'effacer)

Depuis l'ancien système : `sudo dmidecode -s system-manufacturer` (et `system-product-name`, `bios-version`, `bios-release-date`).

| Élément | Valeur relevée |
|---|---|
| Fabricant / modèle | **Beelink** (`AZW`) **Mini S** (gamme Mini S12 Pro), n° de série BN1004KH90819 |
| BIOS | AMI Aptio **ADLNV105** du 12/12/2023 |
| CPU / RAM | Intel N100, 4 cœurs / 4 threads · 16 Go à 3200 MHz |
| SSD | `512GB_SSD_MP28B87213930`, M.2 **SATA** (port P0), 476,9 Go — pas de NVMe |
| Réseau | Realtek RTL8111 `enp1s0`, MAC `e8:ff:1e:d4:f6:07` · Wi-Fi Intel AX101 `wlo1` (coupé) |

**Mise à jour du BIOS : non.** Beelink ne publie pas de BIOS en téléchargement public (envoi par le support au cas par cas) ; aucune version plus récente que 105 documentée ; machine stable. À réévaluer seulement en cas de problème matériel.

## 2. BIOS

Touches : **Suppr** = BIOS · **F7** = menu de démarrage.

### Constats (tout photographié avant modification)

| Menu | Réglage | Valeur | Commentaire |
|---|---|---|---|
| Main | Mots de passe BIOS | aucun | comme PROD-01 |
| Main | Heure | ~2 h de retard | normal : Linux règle l'horloge matérielle en UTC |
| Chipset › SA › Graphics | DVMT Pre-Allocated | 60 Mo | déjà minimal, conservé |
| Advanced › Power & Performance › CPU | PL1 20 W, PL2 désactivé, Turbo, C-states activés | réglage Beelink, conservé |
| Chipset › PCH-IO › SATA | AHCI, Aggressive LPM désactivé | conservé |
| Advanced › USB | Mass Storage Driver Support activé, USB 3.1 Gen 2 | ✅ disque 3,5" et clé USB |
| Advanced › Network Stack | PXE IPv4 activé (option de démarrage n°6) | jamais atteint, conservé |
| Security › Secure Boot | Disabled, mode Setup (aucune clé) | conservé (même raisonnement qu'ADR-016) |
| Advanced › ACPI | Hibernation Enabled, S3 | sans effet sur un serveur, conservé |
| Boot | UEFI, Fast Boot Disabled, délai 1 s | conservé ; la clé USB se choisit par **F7** |
| Advanced › Hardware Monitor | CPU 41 °C, système 42 °C, ventilateur 2 884 tr/min au repos | OK |
| — | Wake On LAN, ErP | **aucune option** dans ce BIOS | WoL à voir côté Linux (`ethtool`) si besoin |

### Réglage modifié

| Menu | Réglage | Avant | Après | Pourquoi |
|---|---|---|---|---|
| Chipset › PCH-IO Configuration | **State After G3** | S5 State | **S0 State** | Redémarre seul après une coupure de courant (coffre de sauvegarde) |

Appliqué par **F4** (Save & Exit).

## 3. Installation d'Ubuntu Server

1. Clé branchée, redémarrer en tapant **F7**, choisir la clé, puis *Try or Install Ubuntu Server*.
2. Premiers écrans identiques à PROD-01 ([installation-ubuntu.md](installation-ubuntu.md) §2) : English, nouvel installeur, clavier `French`/`French`, Ubuntu Server (pas *minimized*), proxy vide, mirror par défaut. Réseau : DHCP sur **`enp1s0`** → `192.168.1.51/24` (bail statique Livebox existant) ; `wlo1` laissé désactivé.

### Stockage — *Custom storage layout* (ADR-026)

Deux disques affichés : **`512GB_SSD_MP28B87213930`** (cible) et **`1USB`** (la clé, 233 Go, dans *USED DEVICES* — ne jamais y toucher). Rien n'est écrit avant la confirmation finale.

1. **Différence avec PROD-01** : l'ancien groupe LVM `ubuntu-vg (existing)` occupait la partition 3 → ligne `ubuntu-vg` › **Delete** d'abord.
2. Ligne `512GB_SSD_…` › **Reformat**, puis **Use As Boot Device** (`/boot/efi`, 1 Go).
3. `free space` › **Add GPT Partition** : `2G`, ext4, `/boot`.
4. `free space` › **Add GPT Partition** : taille vide, **Leave unformatted**.
5. **Create volume group (LVM)** : `vg0`, partition de l'étape 4, sans chiffrement.
6. **`free space` sous `vg0`** (pas la ligne `vg0`) › **Create Logical Volume** : `root`, `80G`, ext4, `/`.
7. Idem : `rancher`, `200G`, ext4, Mount **Other** → `/var/lib/rancher`.
8. *FILE SYSTEM SUMMARY* : 4 lignes, **193,9 Go** libres dans `vg0` → **Done** → **Continue** (action destructive).

### Profil

| Écran | Choix |
|---|---|
| Your name / Server's name / Username | `Gael` / `pprod-01` / `gael` |
| Mot de passe | gestionnaire de mots de passe, entrée « PPROD-01 – gael » |
| Ubuntu Pro | Skip for now |
| SSH | Install OpenSSH server ; aucune clé importée ; mot de passe autorisé (temporaire) |
| Featured snaps | aucun |

Reboot Now, retirer la clé.

## 4. Clés SSH des postes (convention `id_ed25519_<destination>`)

Faire **dev-linux en premier** : `ssh-copy-id` y crée `~/.ssh` sur le serveur, que la commande Windows réutilise.

**dev-linux**
```bash
ssh-keygen -R 192.168.1.51
ssh-keygen -R gbaubu02p
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_pprod_01 -C "gael@dev-linux vers pprod-01"
ssh-copy-id -i ~/.ssh/id_ed25519_pprod_01.pub gael@192.168.1.51
cat >> ~/.ssh/config <<'EOF'   # >> = ajout ; un seul > écraserait le fichier

Host pprod-01
    HostName 192.168.1.51
    User gael
    IdentityFile ~/.ssh/id_ed25519_pprod_01
    IdentitiesOnly yes
EOF
ssh pprod-01 hostname
```

**PC Windows (PowerShell)**
```powershell
ssh-keygen -R 192.168.1.51
ssh-keygen -R gbaubu02p
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519_pprod_01 -C "gael@pc-windows vers pprod-01"
Get-Content $env:USERPROFILE\.ssh\id_ed25519_pprod_01.pub | ssh gael@192.168.1.51 "cat >> ~/.ssh/authorized_keys"
Add-Content -Path $env:USERPROFILE\.ssh\config -Value "`nHost pprod-01`n    HostName 192.168.1.51`n    User gael`n    IdentityFile ~/.ssh/id_ed25519_pprod_01`n    IdentitiesOnly yes"
ssh pprod-01 hostname
```

À la première connexion, vérifier l'empreinte du serveur avant de répondre `yes`.

| Poste | Clé | Empreinte |
|---|---|---|
| PC Windows | `C:\Users\diyod\.ssh\id_ed25519_pprod_01` | `SHA256:EDYvKkGdD7Dss3GD045Qdj4krUHK//jsWdOl9/40x90` |
| dev-linux | `~/.ssh/id_ed25519_pprod_01` | `SHA256:In8i6FCP/VVkG8nxNB2dZHtSAxjbJ+VkX76jab7oJ+w` |

Empreinte **du serveur** `pprod-01` (ED25519) : `SHA256:pCZeH1+XXRDFMQ/hO0/sEAyfFkciYEKJ5RpieGTGv9s`.
Si SSH annonce un jour `REMOTE HOST IDENTIFICATION HAS CHANGED` sans réinstallation : **ne pas se connecter**, enquêter.

## 5. Socle OS

Depuis dev-linux :
```bash
scp ~/claude-projects/prod-01/scripts/socle-os.sh pprod-01:
ssh pprod-01
sudo bash ~/socle-os.sh
```
**Garder cette session ouverte**, tester `ssh pprod-01 hostname` depuis une nouvelle fenêtre (dev-linux) et depuis Windows, puis `sudo reboot`.

Le script a installé 23 mises à jour, réglé Europe/Paris, interdit mots de passe et root en SSH, supprimé `/swap.img`, bloqué Wi-Fi et Bluetooth. Aucune modification du script n'a été nécessaire pour le N100.

## Vérifier

```bash
ssh pprod-01 'hostname; uptime; ip -br a show enp1s0; df -h / /var/lib/rancher; swapon --show; cat /var/run/reboot-required 2>/dev/null || echo "Pas de redémarrage requis"'
```
Depuis Windows : `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password pprod-01` → `Permission denied (publickey)`.
Coupure de courant : débrancher la prise du N100 en marche, rebrancher sans toucher au bouton, puis `ssh pprod-01 uptime`.

| Contrôle | Attendu | Obtenu le 2026-10-10 |
|---|---|---|
| Nom | `pprod-01` | ✅ |
| Réseau | `enp1s0` en `192.168.1.51/24` | ✅ (+ IPv6) |
| `/` · `/var/lib/rancher` | 80 Go · 200 Go, ~190 Go libres dans `vg0` | ✅ 79 Go · 196 Go utiles, 193,89 Go libres |
| Fuseau | Europe/Paris, synchronisé | ✅ |
| Swap | aucun | ✅ |
| Wi-Fi / Bluetooth | Soft blocked | ✅ |
| SSH | clés uniquement, root refusé | ✅ mot de passe refusé depuis Windows |
| Redémarrage | revient seul sur le réseau | ✅ |
| Coupure de courant | redémarre seul (S0 State) | ✅ `up 2 min` sans toucher au bouton |
| Température au repos | — | 51 °C (Ubuntu) |

## Nettoyage des postes (restes de l'ancien N100)

| Poste | Reste | Action |
|---|---|---|
| PC Windows | bloc `Host numobserver-prod` (→ 192.168.1.51, clé `id_ed25519_numobserver_deploy`) dans `.ssh\config` | 🟨 à supprimer (inutile : clé plus autorisée) |
| PC Windows, dev-linux | anciens contextes kubectl vers le K3s du N100 | 🟨 à lister (`kubectl config get-contexts`) puis supprimer |

## Revenir en arrière / dépanner

| Situation | Solution |
|---|---|
| Installation ratée | Réinstaller depuis la clé USB en suivant cette fiche (aucune donnée sur le SSD ; le disque de sauvegarde n'est jamais branché pendant une réinstallation) |
| Plus aucune clé ne fonctionne | Écran + clavier sur le N100, `gael` + mot de passe, ajouter la clé publique dans `~/.ssh/authorized_keys` |
| Réautoriser temporairement les mots de passe | `sudo rm /etc/ssh/sshd_config.d/10-prod01.conf && sudo systemctl restart ssh` (puis relancer `socle-os.sh`) |
| Revenir au comportement « reste éteint après coupure » | BIOS (Suppr) › Chipset › PCH-IO › State After G3 › S5 State |
