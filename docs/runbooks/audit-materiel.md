# Phase 1 — Audit matériel

**Quoi** : vérifier que PROD-01 est sain avant de lui confier des applications, et fixer des **valeurs de référence** pour la surveillance future.
**Réalisé le** : 2026-10-09 (BIOS) et 2026-10-10 (sous Linux) · **Verdict** : ✅ machine saine, apte à la production.

Réglages BIOS : voir [phase-0-1-preparation-bios.md](phase-0-1-preparation-bios.md).

## Outils

```bash
sudo apt install -y smartmontools nvme-cli lm-sensors stress-ng
```

⚠️ Toujours vérifier le **nom de la machine** dans l'invite (`gael@prod-01`) avant de lancer une commande : le dossier `~/claude-projects/prod-01` existe sur dev-linux, ce n'est pas PROD-01.

## 1. SSD — santé (SMART)

```bash
sudo smartctl -a /dev/nvme0          # carnet de santé
sudo smartctl -t short /dev/nvme0    # auto-test court (~2 min, en arrière-plan)
sudo smartctl -l selftest /dev/nvme0 # résultat de l'auto-test
```

Valeurs de référence au 2026-10-10 :

| Indicateur | Valeur | Commentaire |
|---|---|---|
| Modèle | EXT X200E SSD, firmware `00001222`, contrôleur Huawei/HiSilicon (`0x19e5`) | 1,02 To |
| N° de série | `2102357DWVN0RB228131` | utile pour la garantie GMKtec (2 ans) |
| État global | PASSED, Critical Warning `0x00` | |
| Usure (`Percentage Used`) | 0 % | réserve 100 % |
| Heures / cycles | 59 h / 113 | tests d'usine (rodage) |
| Écrit / lu | 1,58 To / 1,78 To | ≈ un passage complet du disque en usine + image Windows + installation |
| Extinctions brutales | 2 | celles de l'installation |
| Erreurs média / journal | 0 / 0 | |
| Auto-test court | Completed without error | |
| Températures (repos) | 32 °C / 42 °C | alerte constructeur à 79 °C |

À surveiller dans le temps : `Percentage Used`, `Media and Data Integrity Errors`, `Critical Warning` (alertes Home Assistant, phase 11).

## 2. Capteurs de température

```bash
sensors
```

| Composant | Capteur `sensors` | Repos | Limite |
|---|---|---|---|
| CPU | `k10temp-pci-00c3` › Tctl | 34 °C | 100 °C |
| RAM ×2 | `spd5118-i2c-1-50` / `-51` › temp1 | 33 °C | 55 °C (high) |
| SSD | `nvme-pci-0500` › Composite | 32 °C | 87 °C |
| GPU intégré | `amdgpu-pci-c600` › edge | 32 °C | — |
| Wi-Fi (coupé) | `mt7921_phy0` | 36 °C | — |

## 3. Test de charge — 30 min, 16 threads à 100 %

Fenêtre 1 (enregistreur, toutes les 30 s → `~/stress-temps.log`) :
```bash
while true; do
  printf '%s CPU=%s RAM1=%s RAM2=%s SSD=%s FREQ=%sMHz\n' "$(date +%T)" \
    "$(sensors k10temp-pci-00c3 | awk '/Tctl/{print $2}')" \
    "$(sensors spd5118-i2c-1-50 | awk '/temp1/{print $2}')" \
    "$(sensors spd5118-i2c-1-51 | awk '/temp1/{print $2}')" \
    "$(sensors nvme-pci-0500 | awk '/Composite/{print $2}')" \
    "$(awk '/MHz/{s+=$4;n++} END{printf "%.0f", s/n}' /proc/cpuinfo)"
  sleep 30
done | tee ~/stress-temps.log
```
Fenêtre 2 (charge) : `stress-ng --cpu 16 --timeout 30m --metrics-brief`

Résultats du 2026-10-10 (10:30 → 11:00) :

| Indicateur | Résultat |
|---|---|
| CPU | 80 °C en 3 min, **plateau à 82 °C** (max 82,5 °C) |
| Fréquence moyenne | **~4 450 MHz tenus 30 min** → aucun bridage thermique |
| RAM | max 44,2 °C |
| SSD | max 37,9 °C |
| Refroidissement | 82 → 46 °C en < 30 s après l'arrêt |
| stress-ng | 16 passés, 0 échec, 0 métrique douteuse |
| Journal noyau | aucun incident thermique ni matériel |

Note : le gouverneur CPU `powersave` (pilote amd-pstate) est **adaptatif**, il ne bride pas (cf. 4,45 GHz sous charge). Conservé.

## 4. Réseau — Intel I226-V (`enp3s0`)

```bash
sudo journalctl -k -b | grep -iE 'igc.*(link (is )?down|reset|timeout|hang)' || echo "Aucune coupure réseau"
ip -s link show enp3s0
```

Résultat du 2026-10-10 : aucune coupure de lien, **0 erreur** en émission et réception.
Le compteur RX `dropped` (~10 % des paquets) compte surtout des trames que le serveur ignore volontairement (diffusions et multicast de la Livebox, protocoles inutilisés) : ce n'est pas une perte de données. Suivre son évolution ; si `errors` augmente ou si des « link down » apparaissent, désactiver l'économie d'énergie de la carte (EEE/ASPM).

## Revenir en arrière

Rien à annuler (lecture seule). Supprimer le journal du test si besoin : `rm ~/stress-temps.log`.
