# Vue d'ensemble — version simple

## Le trajet d'une requête

Quand tu ouvres `https://prism.prod.<domaine>` sur ton téléphone :

1. **Le DNS** traduit le nom en adresse : « prism.prod… = 192.168.1.x (PROD-01) ».
2. **Le navigateur** se connecte à PROD-01 en HTTPS. Le cadenas est valide grâce au certificat wildcard Let's Encrypt `*.prod.gba-lab.win`, que cert-manager obtient et renouvelle tout seul (ADR-022).
3. **Traefik**, le portier de K3s, regarde le nom demandé (`prism`) et transmet à la bonne application.
4. **L'application PRISM** tourne dans un conteneur et lit ses données sur le disque de PROD-01.

Hors de la maison, c'est la même chose, sauf que **Tailscale** crée un tunnel privé entre ton téléphone et PROD-01 avant l'étape 2 : PROD-01 annonce sur Tailscale « `192.168.1.16`, c'est moi », donc la même adresse fonctionne partout (ADR-033).

```
 Téléphone / PC
      │  (hors LAN : tunnel Tailscale)
      ▼
 ┌───────────────────────────── PROD-01 (Ubuntu) ─────────────────────────────┐
 │  K3s                                                                       │
 │   Traefik (HTTPS) ──► prism   ──► données (volume /var/lib/rancher)       │
 │                   ──► wiki                                                 │
 │                   ──► autres projets                                       │
 └────────────────────────────────────────────────────────────────────────────┘
      │ sauvegardes chiffrées (restic)              ▲ surveillance
      ▼                                             │
   N100 + disque 3,5"                        Home Assistant
```

## Le trajet d'un déploiement

1. Je code sur **dev-linux**.
2. Je construis l'image de l'app et je l'envoie sur **GHCR** (GitHub).
3. Je mets à jour la version de l'image dans le fichier `values-prod.yaml` du projet, et je le commite.
4. Je lance une seule commande : `helm upgrade --install … --kube-context prod-01` (ADR-021). Retour arrière : `helm rollback`.

## Ce qui n'existe PAS (volontairement)

- Aucun port ouvert sur la Livebox.
- Aucune app publique sur Internet.
- Aucune autre méthode d'hébergement que K3s.
