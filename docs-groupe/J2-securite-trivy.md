# J2 — Sécurité des images (Trivy)

Scans du 2026-11-26, **Trivy 0.76.2**, scanner `vuln`, sur les images construites par `docker compose build`.
Rapports complets : [`preuves/J2/avant/`](../preuves/J2/avant/) et [`preuves/J2/apres/`](../preuves/J2/apres/).

## Commandes utilisées

Trivy installé localement (`winget install AquaSecurity.Trivy`) **ou** lancé via son image officielle, sans installation :

```bash
# Version installée
trivy image --scanners vuln quiz-backend:local
trivy image --scanners vuln quiz-frontend:local

# Version conteneur (équivalente)
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --scanners vuln quiz-backend:local

# Contrôle bloquant (même règle que la CI) : code de sortie 1 si au moins une CRITICAL
trivy image --scanners vuln --severity CRITICAL --exit-code 1 quiz-backend:local
trivy image --scanners vuln --severity CRITICAL --exit-code 1 quiz-frontend:local
```

`--scanners vuln` : on ne cherche que les CVE (pas les secrets ni les mauvaises configurations, traités séparément).

## Résultats avant / après

| Image | Cible | Avant (images J1) | Après |
|---|---|---|---|
| backend | Paquets système Alpine | 64 (7 HIGH, 21 MEDIUM, 36 LOW) | **0** |
| backend | Paquets npm | 41 (**1 CRITICAL**, 21 HIGH, 16 MEDIUM, 3 LOW) | **2 MEDIUM** |
| frontend | Paquets système Alpine | 236 (**1 CRITICAL**, 56 HIGH, 81 MEDIUM, 96 LOW, 2 UNKNOWN) — `nginx:alpine` en cache (Alpine 3.23.4) | **0** |
| frontend | idem, `nginx:alpine` fraîchement téléchargée (Alpine 3.24.4) | 4 MEDIUM (`libexpat`) — [rapport](../preuves/J2/avant/trivy-frontend-nginx-alpine-recente.txt) | **0** |

Contrôle `--severity CRITICAL --exit-code 1` après correction : **code de sortie 0** pour les deux images.

> **Pourquoi deux résultats « avant » pour le frontend ?** Les deux membres du groupe ont scanné la même image `nginx:alpine`, mais l'un avait une version ancienne en cache local, l'autre une version récente. Même Dockerfile, résultat très différent : une image doit être **reconstruite régulièrement** avec `--pull` (ce que fera la CI) et ses tags/digests suivis.

## Analyse du scan initial

1. **Backend — CRITICAL `tar` (CVE-2026-59873) + 21 HIGH npm** : ces paquets ne sont **pas** des dépendances de l'application. Ils se trouvent dans `/usr/local/lib/node_modules/npm` (et `corepack`), outils livrés avec l'image officielle `node:20-alpine`. Ils servent à *installer* les dépendances, jamais à *exécuter* `node server.js`.
2. **Backend — 7 HIGH système** (`openssl` CVE-2026-14456, `musl` CVE-2026-107891, `zlib`…) : paquets Alpine pour lesquels un correctif est déjà publié.
3. **Backend — Node.js 20** : fin de support en avril 2026, il ne reçoit plus de correctifs.
4. **`glob` et `minimatch` (MEDIUM)** : vraies dépendances transitives de l'app (`resend` → `@react-email/render` → `js-beautify`).
5. **Frontend** : `nginx:alpine` embarque des bibliothèques inutiles pour un site statique (`curl`/`libcurl`, `libxml2`/`libxslt` pour le module XSLT, `tiff` pour image-filter, `libexpat`…) ; c'est là que se trouvaient la CRITICAL `brotli-libs` et la plupart des HIGH. Le multi-stage de J1 évite déjà Node, npm et Vite dans l'image finale.
6. **Frontend — Nginx tournait en root** : pas une CVE, mais une faille Nginx donnerait les droits root dans le conteneur.

## Corrections appliquées

### Backend : Node 24, multi-stage + suppression des outils inutiles

```dockerfile
FROM node:24-alpine AS deps          # étape d'installation : npm est utilisé ici
...
RUN npm ci --omit=dev && npm cache clean --force

FROM node:24-alpine                  # étape d'exécution
RUN apk upgrade --no-cache \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/bin/corepack /usr/local/lib/node_modules/corepack \
           /opt/yarn* /usr/local/bin/yarn /usr/local/bin/yarnpkg
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
USER node
```

- **`node:24-alpine`** (LTS actif) à la place de Node 20 en fin de vie.
- **`apk upgrade --no-cache`** → applique les correctifs système publiés (supprime les 64 CVE Alpine). `--no-cache` évite de laisser l'index APK dans l'image.
- **Suppression de npm / npx / corepack / yarn** → supprime la CRITICAL et les HIGH npm. Vérification : `ls /usr/local/bin` dans le conteneur → seulement `node`, `nodejs`, `docker-entrypoint.sh`.
- Les `node_modules` sont copiés depuis l'étape `deps` avec `--chown=node:node` ; le conteneur tourne en `uid=1000(node)`.

### Frontend : Nginx non-root, variante slim

```dockerfile
FROM node:24-alpine AS build
...
FROM nginxinc/nginx-unprivileged:alpine-slim
USER root
RUN apk upgrade --no-cache
USER nginx
COPY --chown=nginx:nginx nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build --chown=nginx:nginx /app/dist /usr/share/nginx/html
EXPOSE 8080
```

- **`alpine-slim`** : image Nginx officielle sans `curl`, XSLT, image-filter ni njs → beaucoup moins de bibliothèques, donc moins de CVE (image de 42 Mo).
- **`nginx-unprivileged`** : Nginx tourne avec l'utilisateur `nginx` (`uid=101`), pas root. `apk upgrade` nécessite root, d'où le `USER root` temporaire puis le retour à `USER nginx`.
- **Port 8080** : un utilisateur non-root ne peut pas ouvrir un port < 1024. `nginx/nginx.conf` passe à `listen 8080;` et Compose publie `8087:8080`. L'URL locale `http://localhost:8087` ne change pas.

Aucune modification de la logique métier (`server.js`, `main.js`, questions) : uniquement Dockerfiles, configuration Nginx et Compose.

### Non-régression

Après reconstruction (`docker compose up -d --build --pull always`) : `/health` → `200 {"status":"ok"}`, `/` et `/gestion-quiz` → 200, `POST /api/users` → 201, données du volume `pgdata` toujours présentes.

## Vulnérabilités résiduelles (acceptées)

| Paquet | CVE | Sévérité | Version installée → corrigée | Justification |
|---|---|---|---|---|
| glob | CVE-2026-118773 | MEDIUM | 10.5.0 → 14.0.2 | Correctif uniquement en version majeure 14, incompatible avec `js-beautify` qui exige `glob ^10`. Forcer la montée (`overrides`) risquerait de casser `resend`. Le code de l'app n'appelle jamais `glob` avec des entrées utilisateur. |
| minimatch | CVE-2026-118764 | MEDIUM | 9.0.9 → 11.0.1 | Même raison (dépendance de `editorconfig` ← `js-beautify`). |

Ces deux paquets ne servent qu'au formatage HTML d'e-mails dans le SDK Resend ; aucune donnée utilisateur ne leur est passée sous forme de motif de fichier. Risque jugé faible, à réévaluer lors d'une mise à jour de `resend`.

L'image `postgres:16-alpine` (service `db`) n'est pas construite par nous et n'est pas déployée sur Azure (base Neon en cloud) : elle n'entre pas dans le contrôle bloquant.

## Politique retenue pour la CI (J6)

- **CRITICAL** → échec du job (`--exit-code 1 --severity CRITICAL`), contrôle obligatoire avant fusion.
- HIGH / MEDIUM → rapportés (artefact de CI) mais non bloquants ; traités au cas par cas comme ci-dessus.
- `apk upgrade` + build avec `--pull` → les correctifs système récents sont intégrés à chaque nouvelle image.

## Questions probables à l'oral

- *Pourquoi la CRITICAL backend n'était pas « dans votre code » ?* → elle venait de npm, outil inclus dans l'image de base ; on l'a retiré de l'image d'exécution.
- *Pourquoi ne pas simplement prendre une image `node` plus récente ?* → on l'a fait (Node 24), mais npm resterait présent avec ses dépendances ; la vraie correction est de ne pas embarquer d'outils inutiles.
- *Pourquoi Nginx sur 8080 ?* → non-root : un processus sans privilège ne peut pas écouter sur un port < 1024.
- *`apk upgrade` rend-il le build non reproductible ?* → oui en partie (versions système variables) ; compromis assumé au profit des correctifs. Alternative : épingler un digest d'image de base et le mettre à jour régulièrement.
- *Différence Trivy / `npm audit` ?* → `npm audit` ne voit que les dépendances npm du projet ; Trivy analyse toute l'image (OS + tous les `node_modules`, y compris ceux de npm lui-même).
