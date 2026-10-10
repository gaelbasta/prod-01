# Phase 4 — K3s, pare-feu et postes d'administration

**Quoi** : installer Kubernetes (K3s) sur PROD-01, activer le pare-feu, et piloter le cluster depuis le PC Windows et dev-linux.
**Réalisé le** : 2026-10-10 · **Durée** : ~45 min
**Automatisation** : [`scripts/install-k3s.sh`](../../scripts/install-k3s.sh) (version figée, pour la PPROD).

## Versions installées

| Outil | Où | Version |
|---|---|---|
| K3s | PROD-01 | **v1.36.5+k3s1** (containerd 2.3.4) |
| k9s | PROD-01, Windows | v0.51.0 |
| kubectl | Windows / dev-linux | v1.37.1 / v1.37.0 (écart d'une version avec le serveur : supporté) |
| Helm | Windows, dev-linux | v4.3.0 |

---

## 1. Configuration K3s (avant installation)

Fichier versionné : [`k3s/config.yaml`](../../k3s/config.yaml), copié en `/etc/rancher/k3s/config.yaml`.
`tls-san` = noms acceptés par le certificat de l'API (`prod-01`, `192.168.1.16`, `k3s.prod.gba-lab.win`). **À compléter avec le nom Tailscale en phase 12** (puis redémarrer K3s).

## 2. Installation

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.36.5+k3s1" sh -
sudo kubectl get nodes -o wide      # prod-01 Ready
sudo kubectl get pods -A            # coredns, local-path, metrics-server, traefik, svclb : Running
```
Scripts fournis par K3s : `/usr/local/bin/k3s-killall.sh` (tout arrêter), `/usr/local/bin/k3s-uninstall.sh` (désinstaller).

## 3. kubectl et k9s sur PROD-01 (utilisateur gael)

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown gael:gael ~/.kube/config && chmod 600 ~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc     # indispensable sur K3s
kubectl config rename-context default prod-01

curl -sLO https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb
sudo apt install -y ./k9s_linux_amd64.deb && rm k9s_linux_amd64.deb
```

## 4. Pare-feu (ADR-020)

Voir le script ou ADR-020 pour les règles. Points clés : SSH et API (6443) **LAN uniquement**, 80/443 ouverts, réseaux K3s `10.42.0.0/16` et `10.43.0.0/16` autorisés (sinon les pods ne parlent plus au serveur).

Tests après activation :
```bash
kubectl top node                                             # metrics-server OK → règle pods OK
kubectl -n kube-system rollout restart deployment coredns   # repasse Running → règle services OK
kubectl run nettest --rm -it --restart=Never --image=busybox:1.36 -- \
  sh -c 'nslookup example.com && wget -qO- -T 5 http://example.com | head -5'   # DNS + sortie Internet OK
```
Secours : `sudo ufw disable`.

## 5. Postes d'administration

### Kubeconfig « exportable » (préparé sur PROD-01)
Remplace `127.0.0.1` par `k3s.prod.gba-lab.win` et tous les noms `default` par `prod-01` (évite les collisions entre clusters) :
```bash
sed -e 's#https://127.0.0.1:6443#https://k3s.prod.gba-lab.win:6443#' \
    -e 's/: default$/: prod-01/' ~/.kube/config > ~/prod-01.kubeconfig
chmod 600 ~/prod-01.kubeconfig
# … copier sur les postes, puis SUPPRIMER la copie : rm ~/prod-01.kubeconfig
```
⚠️ Un kubeconfig est une **clé administrateur** du cluster : jamais dans Git, jamais partagé, droits `600`.

### PC Windows
```powershell
winget install -e --id Kubernetes.kubectl
winget install -e --id Derailed.k9s
winget install -e --id Helm.Helm
# (rouvrir PowerShell)
Copy-Item $env:USERPROFILE\.kube\config $env:USERPROFILE\.kube\config.backup-2026-10-10   # ancien K3s du N100
scp prod-01:prod-01.kubeconfig $env:USERPROFILE\.kube\config
kubectl get nodes
```
Le kubeconfig Windows ne contient que `prod-01` (l'ancien contexte `default` du N100 est dans la sauvegarde).

### dev-linux
Outils déjà présents. Kubeconfig **fusionné** pour conserver le cluster de dev local `k3d-dev-local` :
```bash
cp ~/.kube/config ~/.kube/config.backup-2026-10-10
scp prod-01:prod-01.kubeconfig ~/.kube/prod-01.kubeconfig
KUBECONFIG=~/.kube/config:~/.kube/prod-01.kubeconfig kubectl config view --flatten > ~/.kube/config.merged
mv ~/.kube/config.merged ~/.kube/config && chmod 600 ~/.kube/config
rm ~/.kube/prod-01.kubeconfig
```
**Règle de sécurité** : sur dev-linux, le contexte **par défaut reste `k3d-dev-local`**. PROD-01 ne se cible qu'explicitement : `kubectl --context prod-01 …`, `helm … --kube-context prod-01`.

## 6. Test de fumée de bout en bout

```bash
kubectl --context prod-01 apply -f tests/smoke-whoami.yaml
```
Ouvrir **http://test.prod.gba-lab.win** → page texte `Hostname: whoami-…`.
Nettoyer : `kubectl --context prod-01 delete namespace test`.

Résultat du 2026-10-10 : ✅ page affichée depuis Firefox sous Windows (chaîne DNS Cloudflare → pare-feu → Traefik → pod validée).

## Revenir en arrière

| Situation | Solution |
|---|---|
| Désinstaller K3s complètement | `sudo /usr/local/bin/k3s-uninstall.sh` (supprime aussi les données de `/var/lib/rancher/k3s`) |
| Pare-feu bloquant | `sudo ufw disable` |
| Restaurer le kubeconfig d'un poste | remettre `config.backup-2026-10-10` à la place de `config` |
| Erreur `x509` depuis un poste | le nom utilisé n'est pas dans `tls-san` : l'ajouter dans `config.yaml`, `sudo systemctl restart k3s` |
