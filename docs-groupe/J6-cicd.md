# J6 — CI/CD avec GitHub Actions

Deux workflows séparés, comme demandé par la consigne :

| Workflow | Quand | Rôle | Accès Azure |
|---|---|---|---|
| [`ci.yml`](../.github/workflows/ci.yml) | chaque **Pull Request** vers `main` | build, scan Trivy **bloquant**, test d'intégration | **aucun** |
| [`deploy.yml`](../.github/workflows/deploy.yml) | **après fusion** dans `main` (ou lancement manuel) | build, re-scan, push ACR, mise à jour Container Apps | OIDC, droits minimum |

Preuves : [`preuves/J6/`](../preuves/J6/).

## J6-A — CI sur Pull Request (`ci.yml`)

3 jobs, tous doivent être verts :

1. **`Build + Trivy (backend)`** et **`Build + Trivy (frontend)`** (même job, matrice sur les 2 images)
   - `docker build --pull` de l'image
   - rapport Trivy complet en artefact (gardé 30 jours) → utile pour voir les HIGH/MEDIUM
   - **contrôle bloquant** : `trivy image --severity CRITICAL --exit-code 1`. Une seule CRITICAL → code de sortie 1 → job rouge. Pas de `continue-on-error`.
2. **`Test d'intégration (Docker Compose)`**
   - `cp .env.example .env` (valeurs fictives) puis `docker compose up --build --wait`
   - `GET /health` à travers Nginx doit renvoyer `{"status":"ok"}`
   - `POST /api/users` doit renvoyer **201** (écriture réelle dans PostgreSQL)
   - logs des conteneurs affichés si ça échoue

Choix :
- **Trivy 0.76.2 figé** et lancé avec l'image officielle `aquasec/trivy` : même version que nos rapports J2, et pas d'action GitHub tierce à qui faire confiance.
- `permissions: contents: read` et **aucun secret** dans ce workflow : du code non relu (une PR) ne peut rien déployer ni lire de secret.
- `concurrency` : si on repousse sur la PR, l'ancienne exécution est annulée.

Première exécution : PR #8, les 3 jobs verts (build+scan ≈ 30-40 s, intégration ≈ 40 s).

### Démonstration contrôlée d'un échec

La consigne demande de montrer qu'une CRITICAL fait échouer la CI **sans** publier d'image dangereuse. On a ouvert une PR de démo (brouillon, jamais fusionnée) qui remplace l'image de base du backend par `node:14-alpine` (Node 14, fin de vie en 2023). Résultat attendu : `Build + Trivy (backend)` rouge, le reste vert. Rien n'est poussé dans l'ACR (le workflow CI n'a pas d'accès Azure). La PR est ensuite fermée.

## Protection de `main`

À faire par l'admin du fork (Loupox78), **après** la première exécution verte de `ci.yml`, sinon on ne peut pas choisir les contrôles :

1. *Settings → Branches → Add branch protection rule* (ou *Rules → Rulesets*), branche `main`
2. ✅ *Require a pull request before merging* + 1 approbation
3. ✅ *Require status checks to pass before merging* → sélectionner exactement :
   - `Build + Trivy (backend)`
   - `Build + Trivy (frontend)`
   - `Test d'intégration (Docker Compose)`
4. ❌ pas de suppression de `main`, ❌ pas de force push
5. Vérifier : un `git push` direct sur `main` doit être refusé, et la PR de démo rouge doit afficher « Merging is blocked ».

Si une option n'est pas disponible avec notre plan GitHub, on le note ici au lieu de prétendre qu'elle est active.

## J6-B — Déploiement après fusion (`deploy.yml`)

Déclenché par un `push` sur `main`, c'est-à-dire **seulement** quand une PR a été fusionnée. Les fusions qui ne touchent que de la doc (`*.md`, `docs-groupe/`, `preuves/`) ne redéploient pas.

Étapes :
1. Connexion Azure avec `azure/login` en **OIDC**
2. Build des 2 images, tag = **hash court du commit**
3. Re-scan Trivy CRITICAL bloquant (on ne publie jamais une image non contrôlée)
4. `docker push` dans l'ACR + affichage des **digests**
5. `az containerapp update --image … --revision-suffix gh-<commit>-<n° d'exécution>` sur le backend et le frontend → **nouvelle révision** pour chacun
6. Liste des révisions + `curl https://<frontend>/health` (avec plusieurs essais à cause du démarrage à froid)

Seule l'image change : les secrets (`database-url`, `jwt-secret`…) et l'ingress posés par `scripts/deploy.sh` ne sont pas touchés, donc le workflow n'a besoin d'aucun secret applicatif.

### Pourquoi OIDC

Avec un « client secret » classique, il faudrait stocker un mot de passe Azure dans GitHub, qui expire et peut fuiter. Avec OIDC :
- GitHub fournit au workflow un jeton signé qui dit « je suis le dépôt `Loupox78/eval-quiz-app`, branche `main` » ;
- Azure fait confiance à ce jeton **uniquement** pour ce dépôt et cette branche (identifiant fédéré `repo:Loupox78/eval-quiz-app:ref:refs/heads/main`) ;
- en échange, il donne un jeton Azure valable quelques minutes.

Une PR ou une autre branche ne peut donc pas se connecter à Azure. Les seuls « secrets » GitHub sont des identifiants publics (client, tenant, abonnement), pas des mots de passe. Bonus : une identité de service n'est pas soumise à la MFA qui nous a bloqués en J3.

### Mise en place (une fois, par Loupox78 qui possède l'abonnement)

```bash
az login
./scripts/setup-github-oidc.sh
```

Le script ([`scripts/setup-github-oidc.sh`](../scripts/setup-github-oidc.sh)) :
- crée l'identité managée `id-quiz-github` avec l'identifiant fédéré GitHub ;
- lui donne le **minimum** : `Reader` sur le groupe, `AcrPush` sur l'ACR, `Contributor` sur les 2 Container Apps seulement (pas sur tout l'abonnement) ;
- crée les secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` dans le dépôt avec `gh`.

Test : *Actions → Deploy → Run workflow* sur `main`.

## Scénario de démo pour la soutenance

1. `git switch -c feature/demo-question` depuis `main`
2. Modifier **une question existante** dans `questions_docker.js` (texte de la question, pas la logique)
3. `git commit` + `git push`, ouvrir la PR vers `main` du fork
4. Montrer les 3 contrôles CI qui tournent puis passent au vert (et le rapport Trivy en artefact)
5. Approbation par l'autre membre, fusion
6. Montrer l'exécution `Deploy` : push ACR avec le tag du commit, puis `az containerapp revision list` → nouvelles révisions `gh-<commit>-…`
7. Ouvrir l'URL Azure et retrouver la question modifiée (la base Neon fonctionne depuis J5)

Ouvrir l'URL 1-2 minutes avant (`min-replicas 0`, démarrage à froid).

## Questions probables à l'oral

- *Pourquoi deux workflows ?* → la PR n'est pas encore relue : elle ne doit avoir ni secret ni droit de déployer. Le déploiement ne se fait qu'après approbation et fusion.
- *Qu'est-ce qui empêche de fusionner si Trivy échoue ?* → le job sort en code 1, et la règle de protection de `main` exige ce contrôle vert.
- *Pourquoi rescanner dans `deploy.yml` ?* → la base de CVE évolue tous les jours ; entre la PR et la fusion une nouvelle CRITICAL a pu sortir.
- *Comment savoir quel code tourne sur Azure ?* → tag d'image = commit, suffixe de révision = commit, digest affiché dans les logs.
- *Comment le pipeline se connecte à Azure ?* → OIDC, identité managée fédérée limitée à `main` de ce dépôt, rôles minimum.
