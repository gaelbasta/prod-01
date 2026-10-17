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
| 6 | Wiki | MkDocs Material déployé avec le profil « static » ; ce repo y devient lisible (ADR-024, ADR-025) — https://wiki.prod.gba-lab.win | ✅ 2026-10-10 |
| 7 | Sauvegardes | Réinstallation du N100 en `pprod-01` (OS + socle, ADR-026) · restic → rest-server append-only, disque 3,5" sur `pprod-01` (ADR-027 à 030) ; sauvegarde chaque nuit à 3 h, entretien le dimanche ; **3 tests de restauration réussis** ([runbook](docs/runbooks/sauvegarde-et-restauration.md)) | ✅ 2026-10-14 |
| 8 | PRISM | Mise en production, puis vraies données — déployé le 2026-10-11 avec des données d'essai (0.9.0) ; le 2026-10-14 : base d'essai effacée, **vraies données importées** (2026 complet), sauvegardées hors de PROD-01 (`9f73631e`), puis **PRISM 1.0.0** (révision Helm 2) | ✅ 2026-10-14 |

## Niveau 2 — Le confort (après PRISM)

| # | Phase | Contenu | Statut |
|---|---|---|---|
| 9 | GitOps (optionnel) | Argo CD, à reconsidérer : les déploiements sont manuels par Helm (ADR-021) | ⏸️ |
| 10 | Secrets dans Git | Sealed Secrets 0.40.0 (ADR-032) : une seule clé, sauvegardée dans le gestionnaire de mots de passe, **restauration testée** ; les 4 secrets créés à la main migrés sans coupure dans `secrets/prod-01/` ([runbook](docs/runbooks/secrets.md)) | ✅ 2026-10-15 |
| 11 | Monitoring | Telegraf → InfluxDB → Grafana (existant sur la machine HA), alertes via Home Assistant, dont « plus de données » (ADR-031) ; 11 règles, test réel réussi ([runbook](docs/runbooks/surveillance.md)) | ✅ 2026-10-15 |
| 12 | Accès distant | Tailscale 1.104.1 sur PROD-01, qui annonce sa seule adresse (`192.168.1.16/32`) : mêmes URL dedans et dehors, PRISM compris (ADR-033) ; test réel en 4G réussi, connexion directe ([runbook](docs/runbooks/acces-distant-tailscale.md)). Famille : plus tard, avec des règles d'accès | ✅ 2026-10-15 |
| 13 | Landing page | Homepage v2.2.0 sur https://home.prod.gba-lab.win : apps découvertes automatiquement (chart plateforme **0.2.0**, bloc `accueil`), liens Infra, CPU/mémoire, date, météo (ADR-034, [runbook](docs/runbooks/accueil.md)) ; wiki, PRISM et Factorydle affichés | ✅ 2026-10-17 |
| 13 bis | Notes | Une app de prise de notes rapide pour poser ses idées, dans l'esprit de [Memos](https://github.com/usememos/memos) : choix de l'outil, hébergement selon le standard (chart plateforme, sauvegarde, accueil), accès téléphone via Tailscale — **Memos 0.31.0** sur https://notes.prod.gba-lab.win, valeurs dans `apps/notes/` (ADR-035) | 🟨 |

## Niveau 3 — La robustesse

| # | Phase | Contenu | Statut |
|---|---|---|---|
| 14 | PPROD | K3s, wildcard `*.pprod.gba-lab.win` et déploiements sur `pprod-01` (l'OS et le socle sont faits en phase 7, ADR-026) | ⬜ |
| 15 | Onduleur | Identifier le modèle, raccorder en USB, NUT, arrêt propre des machines | ⬜ |
| 16 | NAS | Migration de la cible de sauvegarde, copie hors site | ⬜ |
| 17 | Test de reconstruction | Reconstruire PROD-01 de zéro à partir de ce repo + sauvegardes | ⬜ |
