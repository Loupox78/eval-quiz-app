# Preuves J4 — Frontend et backend dans Azure Container Apps (26/11/2026)

| Fichier | Ce qu'il prouve |
|---|---|
| `containerapps-etat-images.png` | 2 apps `Running`, images tirées de l'ACR avec le tag de commit `d063dd1` ; backend **non exposé** (ingress externe `False`), frontend public (`True`) |
| `revision-backend-healthy.png` | Révision active du backend, état `Healthy` |
| `health-http-200.png` | `GET /health` via l'URL publique du frontend → `HTTP/2 200`, `{"status":"ok"}`. L'en-tête `x-powered-by: Express` montre que la réponse vient du backend, relayée par Nginx (communication interservices) |

- URL frontend : https://quiz-frontend.yellowpebble-1a8ee382.switzerlandnorth.azurecontainerapps.io
- Région : `switzerlandnorth` — environnement `cae-quiz-app` (mode WorkloadProfiles)
- Base de données : valeur factice à ce stade (J5 non commencé) ; `/health` ne dépend pas de PostgreSQL.
