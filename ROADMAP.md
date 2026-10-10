# Roadmap PROD-01

Le chantier est découpé en **3 niveaux**. On ne passe au niveau suivant que quand le précédent est terminé et documenté.

Statuts : ⬜ à faire · 🟨 en cours · ✅ fait

## Niveau 1 — Le socle (indispensable avant PRISM)

| # | Phase | Contenu | Statut |
|---|---|---|---|
| 0 | Préparation | Repo `prod-01` sur GitHub, clé USB, BIOS à jour (1.02, pas de flash nécessaire), domaine `gba-lab.win` (Cloudflare, déjà détenu) | ✅ 2026-10-10 |
| 1 | Audit matériel | BIOS réglé, SSD sain (SMART + auto-test), 30 min de charge à 82 °C sans bridage, réseau I226-V sans erreur | ✅ 2026-10-10 |
| 2 | Installation Ubuntu | Partitionnement LVM (ADR-003), hostname `prod-01`, utilisateur, OpenSSH | ✅ 2026-10-09 |
| 3 | Socle OS | IP réservée sur la Livebox, clés SSH (PC Windows + dev-linux), SSH par clé uniquement, mises à jour de sécurité auto, fuseau horaire, swap supprimé, Wi-Fi/BT coupés | ✅ 2026-10-10 |
| 4 | K3s | K3s v1.36.5 mono-nœud, pare-feu ufw, kubectl + k9s + helm sur PROD-01, PC Windows et dev-linux, test de fumée `whoami` OK | ✅ 2026-10-10 |
| 5 | HTTPS + chart plateforme | cert-manager v1.21.2 + Let's Encrypt DNS-01 Cloudflare, wildcard `*.prod.gba-lab.win` servi par défaut, redirection HTTP → HTTPS (ADR-022) · chart plateforme 0.1.0 publié sur GHCR, testé k3d puis prod, mises à jour sans coupure (ADR-023) | ✅ 2026-10-10 |
| 6 | Wiki | MkDocs (thème readthedocs) déployé avec le profil « static » ; ce repo y devient lisible (ADR-024) | 🟨 |
| 7 | Sauvegardes | restic → disque 3,5" sur le N100 ; **test de restauration réussi** | ⬜ |
| 8 | PRISM | Mise en production, puis vraies données | ⬜ |

## Niveau 2 — Le confort (après PRISM)

| # | Phase | Contenu | Statut |
|---|---|---|---|
| 9 | GitOps (optionnel) | Argo CD, à reconsidérer : les déploiements sont manuels par Helm (ADR-021) | ⏸️ |
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
