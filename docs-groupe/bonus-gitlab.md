# Bonus — la même CI sur GitLab

La chaîne officielle du projet est **GitHub Actions** (voir [J6](J6-cicd.md)) : c'est elle qui protège `main` et qui déploie sur Azure. On a ajouté [`.gitlab-ci.yml`](../.gitlab-ci.yml) pour montrer qu'on sait faire la même CI avec GitLab, et pour comparer les deux outils. Ce fichier ne déploie rien et n'utilise aucun secret.

## Ce que fait le pipeline

| Étape | Job | Ce qu'il fait | Bloquant |
|---|---|---|---|
| `build` | `build: [backend]`, `build: [frontend]` | `docker build --pull`, puis `docker save` de l'image en `.tar` (artefact) | ✅ |
| `scan` | `trivy: [backend]`, `trivy: [frontend]` | rapport Trivy complet (artefact 30 jours), puis `--severity CRITICAL --exit-code 1` | ✅ |
| `test` | `compose-test` | `docker compose up`, puis `GET /health` doit répondre | ✅ |

Il tourne sur chaque **Merge Request** et sur `main`.

## Différences avec la version GitHub

| | GitHub Actions | GitLab CI/CD |
|---|---|---|
| Fichier | `.github/workflows/ci.yml` (un fichier par workflow) | `.gitlab-ci.yml` (un seul fichier, avec des `stages`) |
| Docker | déjà installé sur le runner, on utilise `/var/run/docker.sock` | service **Docker-in-Docker** (`docker:dind`), le démon s'appelle `docker` |
| Ports publiés | `http://localhost:8087` | `http://docker:8087` (ils sont sur le conteneur dind, pas sur le job) |
| Passer l'image à Trivy | même machine, Trivy lit le démon Docker | l'image est sauvegardée en `.tar` et passée en **artefact** au job suivant (`trivy image --input`) |
| Plusieurs images | `strategy.matrix` | `parallel.matrix` |
| Rendre un échec non bloquant | `continue-on-error` (on ne l'utilise pas) | `allow_failure` (on ne l'utilise pas) |
| Exiger la CI avant fusion | règle de protection, checks requis | *Settings → Merge requests → Pipelines must succeed* |
| Exiger une approbation | règle de protection, gratuit | **payant** sur gitlab.com (offre Premium) : en gratuit on peut demander une revue mais pas l'imposer |

C'est surtout ce dernier point qui nous a fait garder GitHub comme chaîne officielle : la consigne demande une approbation avant fusion.

## Mettre en place le miroir GitLab

1. Sur gitlab.com : *New project → Import project → GitHub* (ou *Run CI/CD for external repository*), et choisir `Loupox78/eval-quiz-app`.
2. Les deux membres du groupe en **Maintainer** ou **Developer**.
3. *Settings → Repository → Protected branches* : `main`, pas de push direct (*Allowed to push: No one*), fusion par les Maintainers.
4. *Settings → Merge requests* : cocher **Pipelines must succeed**.
5. Ouvrir une MR de test vers `main` et vérifier que les 5 jobs passent.

Les runners partagés de gitlab.com peuvent demander une vérification du compte (téléphone ou carte) avant le premier pipeline, et ils consomment un quota de minutes gratuites.

## Et le déploiement ?

On ne l'a pas fait sur GitLab pour ne pas avoir deux chaînes qui déploient sur les mêmes Container Apps. Ce serait le même principe que sur GitHub :
- un job `deploy` avec `rules: - if: $CI_COMMIT_BRANCH == "main"` ;
- connexion à Azure par **OIDC GitLab** (`id_tokens:` dans le job) ;
- sur l'identité Azure, un identifiant fédéré avec l'émetteur `https://gitlab.com` et le sujet `project_path:<groupe>/<projet>:ref_type:branch:ref:main` ;
- puis les mêmes commandes : `az acr login`, `docker push`, `az containerapp update`.
