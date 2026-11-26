# Preuves J6 — CI/CD

| Preuve | Lien / fichier | Ce qu'elle montre |
|---|---|---|
| CI verte sur PR | PR #8 → onglet *Checks* | `Build + Trivy (backend)`, `Build + Trivy (frontend)`, `Test d'intégration` au vert |
| Rapports Trivy de la CI | artefacts `trivy-backend` / `trivy-frontend` de l'exécution | rapport complet de chaque image |
| CI rouge (démo contrôlée) | PR de démo `demo/trivy-echec` (fermée, jamais fusionnée) | image backend sur `node:14-alpine` → CRITICAL → job rouge |
| Protection de `main` | capture à ajouter (Settings → Branches) | règle active + contrôles requis |
| Fusion bloquée | capture à ajouter | « Merging is blocked » sur la PR rouge |
| Déploiement après fusion | exécution du workflow *Deploy* | push ACR tag = commit, `az containerapp update` |
| Nouvelles révisions | sortie de `az containerapp revision list` | révisions `gh-<commit>-<n>` actives |

Les liens exacts (URL des exécutions) sont dans les descriptions des PR.
