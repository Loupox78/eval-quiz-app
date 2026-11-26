# Démo de soutenance — « Le pipeline qui dit non, puis oui »

Durée : ~5 min de manipulations, réparties pendant la présentation (le pipeline travaille pendant qu'on présente les diapos).
Tout se fait dans le navigateur, sans terminal.

## Avant l'oral (5 min avant)

- [ ] Ouvrir https://g09.labformation.fr et https://g09.labformation.fr/version pour **réveiller** les conteneurs (scale-to-zero) et noter la version affichée.
- [ ] Mehdi connecté à GitHub sur son PC (il approuve les PR).
- [ ] Onglets prêts : dépôt GitHub, onglet *Actions*, l'application, `/version`, dossier `preuves/J6/`.
- [ ] Dernier run *CD* sur `main` au vert.

## Acte 1 — « On essaie de pousser une faille » (le pipeline dit NON)

1. GitHub → `backend/Dockerfile` → crayon ✏️.
2. Remplacer les **deux** lignes `FROM node:24-alpine` par `FROM node:14-alpine` (Node 14 : fin de vie avril 2023).
3. *Commit changes* → **Create a new branch** (ex. `demo/faille`) → *Propose changes* → *Create pull request*.
4. Les checks démarrent. Mehdi **approuve** la PR (« collègue pressé »).
5. Résultat attendu après ~1 min :
   - `Build + Trivy (backend)` **rouge** : vulnérabilités CRITICAL (code de sortie 1) ;
   - `Test de démarrage (Docker Compose)` rouge (le backend ne démarre pas sous Node 14) ;
   - bouton **Merge désactivé** malgré l'approbation.
6. Fermer la PR (*Close pull request*) et supprimer la branche.

> « Même si mon binôme approuve par erreur, la protection de `main` exige les checks Trivy : une image avec une faille critique ne peut pas partir en production. La sécurité ne repose pas sur un humain. »

Preuve de secours si GitHub est lent : `preuves/J6/6-fusion-bloquee-checks-requis.png`, `5-demo-echec-trivy-pr10.png`.

## Acte 2 — « La bonne version part en production » (le pipeline dit OUI)

1. Montrer https://g09.labformation.fr/version → `{"version":"<ancien commit>"}`.
2. GitHub → `questions_cicd.js` → crayon ✏️ → modifier la 1ʳᵉ question, ex. `"[Démo g09] Qu’est-ce que l’intégration continue (CI) ?"`.
3. *Commit changes* → **Create a new branch** → PR.
4. Checks verts (~1–2 min) → Mehdi **approuve** → **Merge**.
5. Onglet *Actions* → workflow **CD** : OIDC → build (avec `APP_VERSION=<commit>`) → Trivy → push ACR → mise à jour Container Apps → `/health` + `/version` (~2 min 30). Pendant ce temps : diapos.
6. Recharger https://g09.labformation.fr/version → **nouveau numéro = commit de fusion** affiché dans GitHub.
7. (Optionnel) Quiz sujet `cicd` : la question « [Démo g09] … » apparaît (ordre aléatoire, ≤ 10 questions).

> « Ce numéro est le commit que je viens de fusionner : il est inscrit dans l'image au build, l'image est taguée avec ce même commit dans l'ACR, et c'est elle que tourne Azure. Traçabilité de bout en bout, sans aucune action manuelle. »

Preuve de secours : `preuves/J6/3-cd-deploiement-reussi.png`, `4-images-deployees-tag-commit.png`.

## Comment fonctionne `/version`

- `Dockerfile` (frontend) : `ARG APP_VERSION=dev` + `ENV APP_VERSION=$APP_VERSION` → la valeur est figée **dans l'image** au build.
- `nginx/templates/default.conf.template` : `location = /version { return 200 '{"version":"${APP_VERSION}"}'; }` (remplacé au démarrage par envsubst, comme `BACKEND_HOST`), en-tête `Cache-Control: no-store`.
- `cd.yml` et `deploy.sh images` : `--build-arg APP_VERSION=<commit court>`. En local (Compose) : `dev`.
- Aucune modification du code métier : uniquement la configuration Nginx et le build.

## Questions possibles

- *Pourquoi pas une variable d'environnement posée au déploiement ?* → l'image doit porter sa propre version : si on redéploie une ancienne image (rollback), `/version` affiche automatiquement le bon numéro.
- *Pourquoi le test Compose échoue aussi dans l'acte 1 ?* → les dépendances du backend exigent un Node récent : le conteneur ne démarre pas, Nginx renvoie 502 sur `/health`.
- *Et si quelqu'un pousse directement sur `main` ?* → interdit par la règle de protection (PR obligatoire, pas de contournement).
