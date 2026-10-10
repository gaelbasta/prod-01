# Phase 3 — Socle OS

**Quoi** : rendre PROD-01 administrable à distance de façon sûre et le mettre dans un état stable.
**Réalisé le** : 2026-10-10 · **Durée** : ~45 min
**Automatisation** : les étapes côté serveur sont reprises dans [`scripts/socle-os.sh`](../../scripts/socle-os.sh) (pour la PPROD N100).

Règle d'or : **ne jamais fermer sa session SSH** pendant une modification de SSH tant que le test depuis une nouvelle fenêtre n'est pas validé.

---

## 1. IP réservée sur la Livebox

- Livebox (http://192.168.1.1, compte `admin`) → **Réseau → DHCP → baux statiques**.
- Entrée : MAC `C8:FF:BF:0B:32:95` → `192.168.1.16`.
- La Livebox refuse le tiret dans le nom : l'entrée s'affiche « prod-1 ». Sans conséquence.

## 2. Accès SSH par clé

Convention : **une clé par couple poste → destination**, nommée `id_ed25519_<destination>`.

| Poste | Clé | Empreinte |
|---|---|---|
| PC Windows | `C:\Users\diyod\.ssh\id_ed25519_prod_01` | `SHA256:dNfJbqR2D9ZIHIaFV6rnLUwcLPaO5eQ8n+PSnUQK5oM` |
| dev-linux | `~/.ssh/id_ed25519_prod_01` | `SHA256:t4y5PQNQrXqsTJgdpc0tBoi1fcytcYgUTQz8ywMY4UU` |

Empreinte **du serveur** PROD-01 (ED25519) : `SHA256:4EnqfxC+Ajy/t/yDrUBRQSzxBDoXLThi893G2LL7FnM`.
Si SSH annonce un jour `REMOTE HOST IDENTIFICATION HAS CHANGED` sans réinstallation : **ne pas se connecter**, enquêter.

### Windows (PowerShell)
```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519_prod_01 -C "gael@pc-windows vers prod-01"
Get-Content $env:USERPROFILE\.ssh\id_ed25519_prod_01.pub | ssh gael@192.168.1.16 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
notepad $env:USERPROFILE\.ssh\config   # ajouter le bloc ci-dessous en fin de fichier
```

### dev-linux
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_prod_01 -C "gael@dev-linux vers prod-01"
ssh-copy-id -i ~/.ssh/id_ed25519_prod_01.pub gael@192.168.1.16
cat >> ~/.ssh/config <<'EOF'   # >> = ajout ; un seul > écraserait le fichier

Host prod-01
    HostName 192.168.1.16
    User gael
    IdentityFile ~/.ssh/id_ed25519_prod_01
    IdentitiesOnly yes
EOF
```

Bloc `config` (identique sur les deux postes) :
```
Host prod-01
    HostName 192.168.1.16
    User gael
    IdentityFile ~/.ssh/id_ed25519_prod_01
    IdentitiesOnly yes
```

## 3. Interdire les mots de passe en SSH (ADR-017)

```bash
sudo tee /etc/ssh/sshd_config.d/10-prod01.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sudo sshd -t && echo "SYNTAXE OK"
sudo systemctl restart ssh
```
Le préfixe `10-` est indispensable : sshd garde la **première** valeur lue, et `50-cloud-init.conf` (installeur) autorise les mots de passe.

## 4. Fuseau horaire et mises à jour (ADR-018)

```bash
sudo timedatectl set-timezone Europe/Paris
sudo apt update && sudo apt full-upgrade -y
cat /etc/apt/apt.conf.d/20auto-upgrades     # deux lignes à "1" = correctifs de sécurité quotidiens
```
Pas de redémarrage automatique. Si `/var/run/reboot-required` existe, redémarrer manuellement (`sudo reboot`).

## 5. Swap supprimé, radios coupées

```bash
sudo swapoff /swap.img
sudo sed -i '\|^/swap.img|d' /etc/fstab
sudo rm /swap.img

sudo apt install -y rfkill          # absent par défaut sur Ubuntu Server 26.04
sudo rfkill block wlan
sudo rfkill block bluetooth
```

---

## Vérifier (après `sudo reboot`)

```bash
hostname; date
ip -br a show enp3s0
timedatectl | grep -E 'Time zone|synchronized'
swapon --show; free -h | grep -i swap
rfkill list | grep -i soft
sudo sshd -T | grep -Ei '^(passwordauthentication|permitrootlogin)'
cat /var/run/reboot-required 2>/dev/null || echo "Pas de redémarrage requis"
```
Depuis un poste : `ssh prod-01 hostname` → `prod-01` ; `ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password prod-01` → `Permission denied (publickey)`.

Résultat du 2026-10-10 : **tout conforme** (IP `.16`, Europe/Paris synchronisé, swap 0B, Wi-Fi/BT `Soft blocked: yes`, mots de passe et root refusés, aucun redémarrage requis).

## Revenir en arrière / dépanner

| Situation | Solution |
|---|---|
| Plus aucune clé ne fonctionne (PC réinstallé, clés perdues) | Écran + clavier sur PROD-01, connexion locale `gael` + mot de passe, puis ajouter la nouvelle clé publique dans `~/.ssh/authorized_keys` |
| Réautoriser temporairement les mots de passe | `sudo rm /etc/ssh/sshd_config.d/10-prod01.conf && sudo systemctl restart ssh` (puis le remettre) |
| Nouveau poste d'administration | Créer `id_ed25519_prod_01` sur ce poste, se connecter depuis un poste déjà autorisé et ajouter la clé publique à `~/.ssh/authorized_keys` |
| Réactiver le Wi-Fi | `sudo rfkill unblock wlan` |
