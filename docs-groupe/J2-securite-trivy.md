# J2 — Sécurité des images (Trivy)

## Commandes utilisées

```bash
# Trivy lancé via son image officielle (pas d'installation nécessaire)
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --scanners vuln quiz-backend:local

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --scanners vuln quiz-frontend:local

# Contrôle bloquant (utilisé en CI) : code de sortie 1 si au moins une CRITICAL
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --severity CRITICAL --exit-code 1 quiz-backend:local
```

`--scanners vuln` : on ne cherche que les CVE (pas les secrets ni les mauvaises configurations, traités séparément).

## Résultats avant / après

| Image | Cible | Avant | Après |
|---|---|---|---|
| backend | Paquets système Alpine | 64 (7 HIGH, 21 MEDIUM, 36 LOW) | **0** |
| backend | Paquets npm | 41 (**1 CRITICAL**, 21 HIGH, 16 MEDIUM, 3 LOW) | **2 MEDIUM** |
| frontend | Paquets système Alpine | 4 MEDIUM | **0** |

Rapports complets : [`preuves/J2/avant/`](../preuves/J2/avant/) et [`preuves/J2/apres/`](../preuves/J2/apres/).

## Analyse du scan initial

1. **CRITICAL `tar` (CVE-2026-59873) + 19 HIGH npm** : ces paquets ne sont **pas** des dépendances de l'application. Ils se trouvent dans `/usr/local/lib/node_modules/npm` et `corepack`, outils livrés avec l'image officielle `node:20-alpine`. Ils servent à *installer* les dépendances, jamais à *exécuter* `node server.js`.
2. **7 HIGH système** (`openssl` CVE-2026-14456, `musl` CVE-2026-107891…) : l'image de base contient des paquets Alpine pour lesquels un correctif est déjà publié.
3. **`glob` et `minimatch` (MEDIUM)** : vraies dépendances transitives de l'app (`resend` → `@react-email/render` → `js-beautify`).
4. **Frontend** déjà presque propre grâce au **multi-stage** de J1 : Node, npm et Vite ne sont pas dans l'image finale.

## Corrections appliquées

### Backend : multi-stage + suppression des outils inutiles
```dockerfile
FROM node:20-alpine AS deps          # étape d'installation : npm est utilisé ici
...
RUN npm ci --omit=dev

FROM node:20-alpine                  # étape d'exécution
RUN apk upgrade --no-cache \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack ...
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
```
- **`apk upgrade --no-cache`** → applique les correctifs système publiés (supprime les 64 CVE Alpine). `--no-cache` évite de laisser l'index APK dans l'image.
- **Suppression de npm / corepack / yarn** → supprime la CRITICAL et les HIGH npm. Vérification : `which npm` dans le conteneur → absent.
- Les `node_modules` sont copiés depuis l'étape `deps` avec `--chown=node:node`, et le conteneur tourne toujours en `USER node`.

### Frontend
- **`RUN apk upgrade --no-cache`** dans l'étape Nginx → les 4 MEDIUM disparaissent.

### Non-régression
Après correction : `docker compose up`, `/health` → `{"status":"ok"}`, `POST /api/users` → utilisateur créé. L'application fonctionne à l'identique.

## Vulnérabilités résiduelles (acceptées)

| Paquet | CVE | Sévérité | Version installée → corrigée | Justification |
|---|---|---|---|---|
| glob | CVE-2026-118773 | MEDIUM | 10.5.0 → 14.0.2 | Correctif uniquement en version majeure 14, incompatible avec `js-beautify` qui exige `glob ^10`. Forcer la montée (`overrides`) risquerait de casser `resend`. Le code de l'app n'appelle jamais `glob` avec des entrées utilisateur. |
| minimatch | CVE-2026-118764 | MEDIUM | 9.0.9 → 11.0.1 | Même raison (dépendance de `editorconfig` ← `js-beautify`). |

Ces deux paquets ne servent qu'au formatage HTML d'e-mails dans le SDK Resend ; aucune donnée utilisateur ne leur est passée sous forme de motif de fichier. Risque jugé faible, à réévaluer lors d'une mise à jour de `resend`.

## Politique retenue pour la CI (J6)

- **CRITICAL** → échec du job (`--exit-code 1 --severity CRITICAL`), contrôle obligatoire avant fusion.
- HIGH / MEDIUM → rapportés (artefact de CI) mais non bloquants ; traités au cas par cas comme ci-dessus.
- `apk upgrade` dans chaque build → les correctifs système récents sont intégrés automatiquement à chaque nouvelle image.

## Questions probables à l'oral

- *Pourquoi la CRITICAL n'était pas « dans votre code » ?* → elle venait de npm, outil inclus dans l'image de base ; on l'a retiré de l'image d'exécution.
- *Pourquoi ne pas simplement utiliser `node:20-alpine` plus récent ?* → ça aide pour Alpine, mais npm resterait présent avec ses dépendances ; la vraie correction est de ne pas embarquer d'outils inutiles.
- *`apk upgrade` rend-il le build non reproductible ?* → oui en partie (versions système variables) ; c'est un compromis assumé au profit des correctifs de sécurité. Alternative : épingler un digest d'image de base et le mettre à jour régulièrement.
- *Différence Trivy / `npm audit` ?* → `npm audit` ne voit que les dépendances npm du projet ; Trivy analyse toute l'image (OS + tous les `node_modules`, y compris ceux de npm lui-même).
