# Preuves J6 — CI/CD GitHub Actions (26/11/2026)

| Fichier | Ce qu'il prouve |
|---|---|
| `1-protection-branche-main.png` | Règle sur `main` : PR obligatoire, **1 approbation**, 3 checks obligatoires (`Build + Trivy (backend)`, `Build + Trivy (frontend)`, `Test de démarrage (Docker Compose)`) |
| `2-pr-9-approuvee-fusionnee.png` | PR #9 (J6) : checks CI verts, approuvée par Mems932, fusionnée |
| `3-cd-deploiement-reussi.png` | Workflow CD déclenché par la fusion : connexion Azure **OIDC**, build, Trivy CRITICAL, push ACR, mise à jour des Container Apps, `/health` — succès en 2 min 19 s |
| `4-images-deployees-tag-commit.png` | Les deux Container Apps tournent sur l'image `:9eadf79` = commit de fusion de la PR #9 (déploiement manuel précédent : `:d063dd1`) |

Premier run CD en échec (`AADSTS700213`, format du *subject* OIDC) puis relancé avec succès après correction : voir `docs-groupe/J6-cicd.md`, section « Incident ».
