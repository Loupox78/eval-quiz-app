# Preuves J6 — CI/CD GitHub Actions (26/11/2026)

## Captures

| Fichier | Ce qu'il prouve |
|---|---|
| `1-protection-branche-main.png` | Règle sur `main` : PR obligatoire, **1 approbation**, 3 checks obligatoires (`Build + Trivy (backend)`, `Build + Trivy (frontend)`, `Test de démarrage (Docker Compose)`) |
| `2-pr-9-approuvee-fusionnee.png` | PR #9 (J6) : relue et **approuvée par Mems932** (commentaire de revue), fusionnée dans `main` (commit `9eadf79`), « 3 checks passed » |
| `3-cd-deploiement-reussi.png` | Workflow CD déclenché par la fusion : connexion Azure **OIDC**, build, Trivy CRITICAL, push ACR, mise à jour des Container Apps, `/health` — succès en 2 min 19 s |
| `4-images-deployees-tag-commit.png` | Les deux Container Apps tournent sur l'image `:9eadf79` = commit de fusion de la PR #9 (déploiement manuel précédent : `:d063dd1`) |
| `5-demo-echec-trivy-pr10.png` | Démo contrôlée PR #10 : backend sur `node:14-alpine` → Trivy trouve 2 CRITICAL (`form-data` CVE-2025-7783) → code de sortie 1, job rouge ; aucune image publiée |

## Où retrouver les autres preuves

| Preuve | Où | Ce qu'elle montre |
|---|---|---|
| CI verte sur PR | PR #9 → onglet *Checks* | les 3 checks obligatoires au vert |
| Rapports Trivy de la CI | artefacts `trivy-backend` / `trivy-frontend` de l'exécution | rapport complet de chaque image |
| CI rouge (démo contrôlée) | PR #10 (jamais fusionnée), exécution [45831008873](https://github.com/Loupox78/eval-quiz-app/actions/runs/45831008873) | contrôle bloquant Trivy en échec |
| Fusion bloquée | capture à ajouter (PR de démo) | « Merging is blocked » tant que la CI est rouge |
| Déploiement après fusion | exécution du workflow *CD* sur `main` | push ACR tag = commit, `az containerapp update` |
| Nouvelles révisions | `az containerapp revision list -n quiz-backend -g rg-quiz-app -o table` | nouvelle révision active avec l'image du commit fusionné |

Premier run CD en échec (`AADSTS700213`, format du *subject* OIDC) puis relancé avec succès après correction : voir `docs-groupe/J6-cicd.md`, section « Incident ».
