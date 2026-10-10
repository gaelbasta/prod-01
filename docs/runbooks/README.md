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
| [installation-pprod-01.md](installation-pprod-01.md) (réinstallation du N100 : Ubuntu Server + socle) | 7 | 🟨 en cours |
| sauvegarde-et-restauration.md | 7 | ⬜ |
| redemarrer-prod-01.md | — | ⬜ |
