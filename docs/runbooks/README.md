# Runbooks

Une fiche par opération. Chaque fiche répond à : **quoi · comment · vérifier · revenir en arrière**.
Les fiches sont écrites au fur et à mesure, à partir de ce qui a *réellement* été fait.

| Fiche | Phase | Statut |
|---|---|---|
| [phase-0-1-preparation-bios.md](phase-0-1-preparation-bios.md) | 0–1 | 🟨 en cours |
| [audit-materiel.md](audit-materiel.md) (SSD, températures, charge, réseau) | 1 | ✅ |
| [installation-ubuntu.md](installation-ubuntu.md) | 2 | ✅ |
| [socle-os.md](socle-os.md) (IP, SSH, mises à jour, swap, radios) | 3 | ✅ |
| [installation-k3s.md](installation-k3s.md) (K3s, pare-feu, postes d'admin, test de fumée) | 4 | ✅ |
| [https-certificats.md](https-certificats.md) (cert-manager, Let's Encrypt, wildcard, redirection HTTPS) | 5 | ✅ |
| [deployer-une-app.md](deployer-une-app.md) (chart plateforme : déployer, mettre à jour, revenir en arrière, publier le chart) | 5 | ✅ |
| [wiki.md](wiki.md) (construire, publier, mettre à jour le wiki ; ajouter un projet) | 6 | ✅ |
| [installation-pprod-01.md](installation-pprod-01.md) (N100 : BIOS, Ubuntu Server, socle, clés SSH) | 7 | ✅ |
| [sauvegarde-et-restauration.md](sauvegarde-et-restauration.md) (disque, coffre, sauvegarde nocturne, entretien, restaurer, garde-fous) | 7 | ✅ |
| [secrets.md](secrets.md) (Sealed Secrets : principe en deux minutes, créer / changer / migrer un secret, restaurer la clé) | 10 | ✅ |
| [surveillance.md](surveillance.md) (Telegraf, InfluxDB, alertes Grafana, que faire quand une alerte sonne) | 11 | ✅ |
| [accueil.md](accueil.md) (page d'accueil Homepage : faire apparaître une app, modifier liens et widgets, mettre à jour) | 13 | ✅ |
| [acces-distant-tailscale.md](acces-distant-tailscale.md) (Tailscale : principe, installation, test en 4G, ajouter un appareil, famille, retour arrière) | 12 | ✅ |
| redemarrer-prod-01.md | — | ⬜ |
