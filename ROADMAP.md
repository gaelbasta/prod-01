# Roadmap PROD-01

Le chantier est découpé en **3 niveaux**. On ne passe au niveau suivant que quand le précédent est terminé et documenté.

Statuts : ⬜ à faire · 🟨 en cours · ✅ fait

## Niveau 1 — Le socle (indispensable avant PRISM)

| # | Phase | Contenu | Statut |
|---|---|---|---|
| 0 | Préparation | Repo `prod-01`, clé USB Ubuntu Server 26.04.1 LTS, achat du nom de domaine, mise à jour du BIOS (sous Windows) | 🟨 |
| 1 | Audit matériel | ✅ BIOS réglé (2026-10-09). Reste, sous Linux : santé du NVMe (SMART), températures sous charge, stabilité réseau I226-V | 🟨 |
| 2 | Installation Ubuntu | Partitionnement LVM (ADR-003), hostname `prod-01`, utilisateur, OpenSSH | ✅ 2026-10-09 |
| 3 | Socle OS | IP réservée sur la Livebox, clés SSH (PC Windows + dev-linux), SSH par clé uniquement, mises à jour de sécurité auto, fuseau horaire, swap supprimé, Wi-Fi/BT coupés | ✅ 2026-10-10 |
| 4 | K3s | Installation mono-nœud, kubectl + k9s sur PROD-01, PC Windows et dev-linux | ⬜ |
| 5 | HTTPS + modèle d'app | DNS du domaine, certificat wildcard, premier modèle « app » et « static », déploiement par `kubectl apply -k` | ⬜ |
| 6 | Wiki | MkDocs déployé avec le modèle « static » ; ce repo y devient lisible | ⬜ |
| 7 | Sauvegardes | restic → disque 3,5" sur le N100 ; **test de restauration réussi** | ⬜ |
| 8 | PRISM | Mise en production, puis vraies données | ⬜ |

## Niveau 2 — Le confort (après PRISM)

| # | Phase | Contenu | Statut |
|---|---|---|---|
| 9 | GitOps | Argo CD : déployer = faire un commit. Reprend les mêmes dossiers que la phase 5, sans rien refaire | ⬜ |
| 10 | Secrets dans Git | Sealed Secrets (remplace les secrets créés à la main) | ⬜ |
| 11 | Monitoring | Capteurs et alertes dans Home Assistant, dont l'alerte « pas de données » | ⬜ |
| 12 | Accès distant | Tailscale sur PROD-01, mêmes URL dedans et dehors | ⬜ |
| 13 | Landing page | Homepage, avec découverte automatique des apps | ⬜ |

## Niveau 3 — La robustesse

| # | Phase | Contenu | Statut |
|---|---|---|---|
| 14 | PPROD | Réinstallation du N100 avec les scripts de PROD-01 (= premier test de reconstruction) | ⬜ |
| 15 | Onduleur | Identifier le modèle, raccorder en USB, NUT, arrêt propre des machines | ⬜ |
| 16 | NAS | Migration de la cible de sauvegarde, copie hors site | ⬜ |
| 17 | Test de reconstruction | Reconstruire PROD-01 de zéro à partir de ce repo + sauvegardes | ⬜ |
