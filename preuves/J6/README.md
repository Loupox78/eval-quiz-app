# Preuves J6 — CI/CD

| Preuve | Où | Ce qu'elle montre |
|---|---|---|
| CI verte sur PR | PR #9 → onglet *Checks* | `Build + Trivy (backend)`, `Build + Trivy (frontend)`, `Test de démarrage (Docker Compose)` au vert |
| Rapports Trivy de la CI | artefacts `trivy-backend` / `trivy-frontend` de l'exécution | rapport complet de chaque image |
| CI rouge (démo contrôlée) | PR #10 (brouillon, jamais fusionnée), exécution [45831008873](https://github.com/Loupox78/eval-quiz-app/actions/runs/45831008873) | image backend sur `node:14-alpine` → Trivy trouve 2 CRITICAL (`form-data` CVE-2025-7783) → **code de sortie 1**, job rouge ; aucune image publiée |
| Protection de `main` | capture à ajouter (Settings → Branches) | règle active + contrôles requis |
| Fusion bloquée | capture à ajouter (PR #10) | « Merging is blocked » tant que la CI est rouge |
| Déploiement après fusion | exécution du workflow *CD* sur `main` | push ACR tag = commit, `az containerapp update` |
| Nouvelles révisions | `az containerapp revision list -n quiz-backend -g rg-quiz-app -o table` | nouvelle révision active avec l'image du commit fusionné |
