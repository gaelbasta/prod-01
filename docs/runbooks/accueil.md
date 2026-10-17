# Page d'accueil : Homepage (https://home.prod.gba-lab.win)

**Quoi** : une page qui rassemble toutes les apps de PROD-01, les liens de l'infra et l'état du serveur. Les apps y apparaissent **toutes seules** dès qu'elles activent le bloc `accueil` du chart plateforme.
**Mis en service le** : 2026-10-16/17 (phase 13) · **Décision** : [ADR-034](../../DECISIONS.md)
**Fichiers** : [`platform/homepage/`](../../platform/homepage/) (manifestes + `config/`) · chart [`charts/plateforme/`](../../charts/plateforme/README.md) (bloc `accueil`, depuis 0.2.0)

---

## En deux minutes

```
 app (chart plateforme 0.2.0)                       Homepage (namespace homepage)
 values-prod.yaml : accueil.enabled: true   ──►   lit les Ingress du cluster (droits lecture seule)
   → annotations gethomepage.dev/* sur l'Ingress    → tuile dans « Apps » : nom, icône, description
                                                    → point vert si le pod de l'app tourne
 platform/homepage/config/*.yaml            ──►   réglages, liens « Infra », widgets (CPU/mémoire, date, météo)
```

- **Une app = deux lignes** dans son `values-prod.yaml` (plus la version 0.2.0 du chart). Rien à faire dans Homepage.
- **Les liens Infra et les widgets** sont écrits à la main dans `platform/homepage/config/`. Après modification : `apply -k` (Homepage redémarre tout seul avec la nouvelle configuration).
- **Liens par adresse IP** (`192.168.1.26`), pas `homeassistant.local` : ils marchent aussi hors de la maison via Tailscale (ADR-033).
- Homepage ne garde **aucune donnée** : rien à sauvegarder, tout se reconstruit depuis ce repo.

| Élément | Valeur (2026-10-17) |
|---|---|
| Image | `ghcr.io/gethomepage/homepage:v2.2.0` (publique, version figée) |
| Apps affichées | Factorydle, Notes (depuis le 2026-10-17), PRISM, Wiki (rubrique « Apps », triées par nom) |
| Liens Infra | Grafana, Home Assistant, Tailscale, GitHub, images GHCR |
| Widgets | CPU / mémoire de PROD-01 (metrics-server de K3s), date et heure, météo de Gorges (Open-Meteo) |
| Surveillance | `https://home.prod.gba-lab.win/api/healthcheck` depuis `pprod-01` (alerte « App de PROD-01 injoignable ») |

---

## A. Mise en place — ✅ 2026-10-16/17

1. **Chart plateforme 0.2.0** (bloc `accueil`, `enableServiceLinks: false`, contexte dans les NOTES) : testé sur k3d, publié (`sha256:3976452f…`, tag `plateforme-0.2.0`) — procédure D de [deployer-une-app.md](deployer-une-app.md).
2. **Homepage** (sur dev-linux, dans `~/claude-projects/prod-01`) :
   ```bash
   kubectl kustomize platform/homepage | grep -E '^kind:'        # 8 objets
   kubectl --context prod-01 create namespace homepage            # 1er déploiement seulement (voir piège 1)
   kubectl --context prod-01 apply -k platform/homepage --dry-run=server
   git add -A && git commit -m "…" && git push                    # commit AVANT d'appliquer
   kubectl --context prod-01 apply -k platform/homepage
   kubectl --context prod-01 -n homepage rollout status deploy/homepage --timeout=180s
   curl -s -o /dev/null -w '%{http_code}\n' https://home.prod.gba-lab.win/   # 200
   ```
3. **Les apps** : wiki (repo wiki), PRISM et Factorydle (via Claude Code dans leur repo, puis `helm upgrade` par Gael) passées en 0.2.0 avec leur bloc `accueil`. PRISM : le contournement `PRISM_PORT` dans `env` est devenu inutile (0.2.0) et a été retiré du fichier de valeurs.

### Pièges rencontrés

1. **`--dry-run=server` au premier déploiement** : erreurs `namespaces "homepage" not found` sur tous les objets du namespace. Le test à blanc *simule* la création du namespace sans la faire. Solution : `kubectl create namespace homepage` d'abord (sans risque), puis le test à blanc.
2. **Réglages ignorés au tout premier démarrage** (version affichée en bas de page, météo en anglais, liens en colonne) alors que `settings.yaml` était bien monté : Homepage avait servi sa page pré-construite. `Ctrl+F5` ne suffit pas ; **`kubectl --context prod-01 -n homepage rollout restart deploy/homepage`** règle le problème. Ensuite, chaque `apply -k` qui modifie `config/` crée un nouveau pod, qui relit tout.

---

## B. Faire apparaître une app

Dans le `deploy/values-prod.yaml` du projet : la commande d'en-tête en `--version 0.2.0` (ou plus), et
```yaml
accueil:
  enabled: true
  name: Factorydle                          # vide = nom de la release
  icon: mdi-factory                         # Material Design Icons (mdi-…), Simple Icons (si-…), ou URL
  description: Jeu idle inspiré de Satisfactory
  # group: Apps                             # rubrique (défaut : Apps)
```
Commit + push, puis le `helm upgrade` habituel. Vérifier :
```bash
kubectl --context prod-01 -n <projet> get ingress <projet> -o jsonpath='{.metadata.annotations}{"\n"}'   # gethomepage.dev/…
```
La tuile apparaît dans la minute. Icônes : https://pictogrammers.com/library/mdi/ (préfixe `mdi-`).

**Retirer une app de la page** : `enabled: false` (ou supprimer le bloc), puis `helm upgrade`.

## C. Modifier les liens, les widgets ou les réglages

1. Modifier `platform/homepage/config/services.yaml` (liens Infra), `widgets.yaml` (bandeau du haut) ou `settings.yaml` (titre, thème, disposition des rubriques). Docs : https://gethomepage.dev/configs/
2. `kubectl kustomize platform/homepage >/dev/null && echo OK` (fichiers lisibles), `git diff`, commit + push.
3. `kubectl --context prod-01 apply -k platform/homepage` → le ConfigMap change de nom (suffixe), Homepage redémarre avec la nouvelle configuration. Recharger la page.

## D. Mettre à jour Homepage

1. Lire les notes de version : https://github.com/gethomepage/homepage/releases (les versions majeures peuvent changer la configuration).
2. Changer le tag dans `platform/homepage/deployment.yaml` (jamais `latest`), commit + push, `apply -k`, `rollout status`, vérifier la page.
3. Retour arrière : remettre l'ancien tag (`git revert`), `apply -k`.

## E. Revenir en arrière / dépanner

| Situation | Solution |
|---|---|
| Page en erreur « host not allowed » | le nom utilisé n'est pas dans `HOMEPAGE_ALLOWED_HOSTS` (`deployment.yaml`) ; regarder `kubectl --context prod-01 -n homepage logs deploy/homepage` |
| Une app n'apparaît pas | annotations absentes sur son Ingress (chart < 0.2.0 ou `accueil.enabled` absent) ; sinon `rollout restart deploy/homepage` |
| Point de l'app rouge / gris | le pod de l'app ne tourne pas : `kubectl --context prod-01 -n <projet> get pods` |
| Widget CPU/mémoire vide | metrics-server de K3s : `kubectl --context prod-01 top node` |
| Tout retirer | `kubectl --context prod-01 delete -k platform/homepage` (aucune donnée perdue ; les annotations des apps restent, sans effet) |
| Revenir au chart 0.1.0 pour une app | `helm rollback <projet> -n <projet> --kube-context prod-01` |
