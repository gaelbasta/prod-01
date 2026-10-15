# Accès distant : Tailscale (mêmes adresses dedans et dehors)

**Quoi** : depuis l'extérieur (4G, autre Wi-Fi), mes appareils ouvrent **les mêmes adresses** qu'à la maison (`https://prism.prod.gba-lab.win`, `https://wiki.prod.gba-lab.win`…) grâce à Tailscale. Rien n'est ouvert sur la Livebox.
**Mis en service le** : 2026-10-15 (phase 12) · **Décisions** : [ADR-010](../../DECISIONS.md), [ADR-033](../../DECISIONS.md)

---

## En deux minutes

**L'image** : un couloir privé entre ta poche et la maison, dont seuls tes appareils ont la clé.

- Le DNS public répond **toujours** `*.prod.gba-lab.win → 192.168.1.16`, même en 4G. Sans Tailscale, cette adresse privée est injoignable de dehors (c'est voulu).
- **PROD-01 est sur Tailscale** (`100.110.247.64`) et annonce **une seule route** : « `192.168.1.16`, c'est moi » (`192.168.1.16/32`).
- En 4G avec Tailscale activé, le téléphone obtient `192.168.1.16` par le DNS et Tailscale l'achemine **par le tunnel, directement jusqu'à PROD-01**. Pas de changement de DNS, de certificat ou d'app.
- Seuls **80/443** (les apps web) sont utiles à travers ce chemin : SSH et l'API Kubernetes de PROD-01 restent limités au LAN par son pare-feu.

```
Téléphone (4G, Tailscale ON)
  1. DNS public : prism.prod.gba-lab.win → 192.168.1.16
  2. route Tailscale 192.168.1.16/32 → prod-01 (100.110.247.64)
  3. tunnel chiffré (direct, ou relais Tailscale)  ─────────►  PROD-01 : tailscale0 → Traefik :443 → PRISM
```

**Le réseau Tailscale (tailnet `tail91cc22.ts.net`, compte Google `diyode@gmail.com`, 1 utilisateur) au 2026-10-15** :

| Machine | Adresse Tailscale | Routes annoncées (approuvées) | Clé | Rôle |
|---|---|---|---|---|
| `prod-01` | `100.110.247.64` | `192.168.1.16/32` | expiration désactivée | accès direct aux apps de PROD-01 |
| `homeassistant` | `100.106.46.81` | `192.168.1.0/24` + 2 plages IPv6 du LAN ; exit node proposé | expiration désactivée | accès au reste du LAN (antérieur à ce chantier, géré dans le projet HA) |
| `redmi-note-12-pro-5g` | `100.118.137.26` | — | — | mon téléphone |

Pourquoi deux routes ne se gênent pas : pour `192.168.1.16`, la route `/32` de PROD-01 est **plus précise** que le `/24` de HA, donc c'est elle qui est prise ; pour le reste du LAN, rien ne change.

| Réglage de la console (2026-10-15) | Valeur |
|---|---|
| Règles d'accès | par défaut : *All users and devices → All users and devices, all ports* (suffisant tant que je suis seul) |
| DNS | MagicDNS activé, aucun serveur DNS imposé (chaque appareil garde le DNS de son réseau) |

---

## A. Mise en place sur PROD-01 — ✅ 2026-10-15

> ⚠️ Sur **PROD-01** (`ssh prod-01`, invite `gael@prod-01`), avec une **deuxième session SSH ouverte**.

### A1. Installer Tailscale (dépôt officiel)

```bash
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/resolute.noarmor.gpg \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/resolute.tailscale-keyring.list \
  | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt-get update
sudo apt-get install -y tailscale                  # + paquet tailscale-archive-keyring (gère la clé)
tailscale version | head -1                        # 1.104.1
systemctl is-active tailscaled                     # active (démarre au boot)
tailscale status                                   # Logged out.
sysctl net.ipv4.ip_forward                         # = 1 (déjà activé par K3s)
```

### A2. Connecter PROD-01

```bash
sudo tailscale up --hostname=prod-01 --advertise-routes=192.168.1.16/32 \
  --accept-dns=false --accept-routes=false
```

| Option | Pourquoi |
|---|---|
| `--advertise-routes=192.168.1.16/32` | annoncer **sa seule adresse** LAN, pas tout le réseau |
| `--accept-dns=false` | garder le DNS de la Livebox : sinon Tailscale le remplacerait (`100.100.100.100`), ce qui toucherait aussi le DNS des pods K3s |
| `--accept-routes=false` | **ignorer** le `192.168.1.0/24` annoncé par HA : sinon PROD-01 enverrait son trafic local dans le tunnel |

La commande affiche un lien `https://login.tailscale.com/a/…` : l'ouvrir et valider **dans les 2 minutes**, la commande répond alors `Success.`

**Piège rencontré** : validation trop tardive → la commande ne rend pas la main et le journal (`sudo journalctl -u tailscaled`) montre `register request: http 410: auth path not found` ; la console affiche `prod-01` avec un point **gris**. Correction : **Ctrl+C**, relancer la même commande, valider aussitôt le **nouveau** lien. (La fiche existante a été reprise, pas de doublon.)

Avertissements affichés, **sans gravité** ici : `IPv6 forwarding is disabled` (on n'annonce que de l'IPv4) et `UDP GRO forwarding is suboptimally configured` (optimisation de débit).

### A3. Console Tailscale (https://login.tailscale.com/admin/machines), ligne `prod-01`

1. `…` → **Disable key expiry** (sinon déconnexion au bout de 180 jours).
2. `…` → **Edit route settings** → cocher **`192.168.1.16/32`** → **Save** (une route non approuvée n'est pas utilisée).

### A4. Vérifier

Sur PROD-01 :
```bash
tailscale status                     # prod-01, homeassistant, téléphone
                                     # « Some peers are advertising routes but --accept-routes is false » = normal (voulu)
tailscale ip -4                      # 100.110.247.64
ip route get 192.168.1.26            # … dev enp3s0 … (le LAN passe toujours par le câble, pas par tailscale0)
resolvectl status | grep -m3 -E 'DNS Server|Current DNS'    # 192.168.1.1 (Livebox), pas 100.100.100.100
kubectl get nodes                    # Ready
```
Depuis dev-linux : `kubectl --context prod-01 get nodes && ssh prod-01 hostname` → inchangé.

**Test réel en 4G** (téléphone : Wi-Fi coupé, Tailscale activé) — sur PROD-01 pendant qu'on ouvre PRISM puis le wiki sur le téléphone :
```bash
sudo timeout 90 tcpdump -ni tailscale0 -c 10 'tcp port 443'
# → 100.118.137.26.xxxxx > 192.168.1.16.443 … : le téléphone arrive DIRECTEMENT par le tunnel de PROD-01
tailscale status | grep redmi
# → active; direct [2a01:…]:49632 …  (connexion directe en IPv6, sans relais)
```
Constaté le 2026-10-15 : PRISM (connexion comprise) et wiki affichés en 4G ; paquets reçus sur `tailscale0` ; connexion **directe**.

---

## B. Ajouter un appareil (à moi)

1. Installer l'app Tailscale (Android, Windows…), se connecter avec le compte Google `diyode@gmail.com`.
2. Rien d'autre : la route `192.168.1.16/32` est utilisée automatiquement (Android, iOS, Windows). **Sur un Linux** : `sudo tailscale up --accept-routes`… ⚠️ **jamais sur dev-linux ni sur une machine du LAN** (elle enverrait son trafic local dans le tunnel) — un poste Linux de la maison n'a pas besoin de Tailscale pour joindre PROD-01.
3. Tester en 4G / hors de la maison : `https://wiki.prod.gba-lab.win`.

## C. Donner l'accès à Estelle et Anna — 🔜 à décider (ADR-033)

Aujourd'hui, la règle d'accès par défaut laisse **tout appareil du tailnet joindre tout**, y compris le LAN entier via HA et donc le SSH de PROD-01 (le trafic passé par HA y arrive avec l'adresse LAN de HA, autorisée par le pare-feu). Acceptable tant que je suis le seul utilisateur (SSH par clé uniquement) ; **avant d'ajouter la famille**, écrire des règles d'accès du type : moi → tout ; famille → `192.168.1.16:443` (et `:80`) seulement. Choix à faire à ce moment-là : comptes séparés (invitation) ou appareils connectés avec mon compte.

## D. Entretien

| Quoi | Comment |
|---|---|
| Mises à jour | dépôt Tailscale **non couvert** par `unattended-upgrades` (origines Ubuntu seulement, comme Telegraf) : `sudo apt update && sudo apt upgrade` manuel ~1×/mois. La console signale les versions en retard (flèche rouge). |
| Après un redémarrage de PROD-01 | `tailscaled` repart seul et se reconnecte (réglages conservés) ; contrôle : `tailscale status` |
| État du lien | `tailscale status`, `tailscale netcheck` (qualité du réseau), journal : `sudo journalctl -u tailscaled -n 50` |

## E. Revenir en arrière

| Situation | Commande (sur PROD-01) |
|---|---|
| Couper l'accès distant tout de suite | `sudo tailscale down` (PROD-01 reste inscrit ; `sudo tailscale up` + mêmes options pour revenir) — l'accès via HA, lui, continue tant que HA annonce le LAN |
| Retirer PROD-01 du tailnet | `sudo tailscale logout`, puis supprimer la machine dans la console |
| Désinstaller | `sudo apt-get purge -y tailscale tailscale-archive-keyring` puis `sudo rm /etc/apt/sources.list.d/tailscale.list` et `sudo apt-get update` |
| Appareil perdu ou volé | console → machine → `…` → **Remove** (il perd l'accès immédiatement) |
