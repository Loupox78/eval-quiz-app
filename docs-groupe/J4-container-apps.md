# J4 — Frontend et backend dans Azure Container Apps

Les commandes et les incidents détaillés (mode Express, quota de région, `UNAUTHORIZED`) sont dans [J3-azure-acr.md](J3-azure-acr.md) car on a fait J3 et J4 à la suite avec le même script. Ici on résume ce qui tourne et pourquoi c'est configuré comme ça.

Preuves : [`preuves/J4/`](../preuves/J4/).

## Ce qui tourne sur Azure

Tout est dans le groupe `rg-quiz-app`, sur l'abonnement Azure for Students de Loupox78, région `switzerlandnorth`.

| Ressource | Nom | Réglages importants |
|---|---|---|
| Environnement Container Apps | `cae-quiz-app` | mode **WorkloadProfiles** (profil Consumption), logs dans Log Analytics |
| Container App backend | `quiz-backend` | image `quiz-backend:<commit>` depuis l'ACR, **ingress interne**, port 3007, HTTP autorisé en interne |
| Container App frontend | `quiz-frontend` | image `quiz-frontend:<commit>` depuis l'ACR, **ingress externe** (HTTPS), port 8080 |
| Identité managée | `id-quiz-acrpull` | rôle `AcrPull` sur l'ACR, utilisée par les 2 apps pour tirer les images |

Les deux apps : 0,25 vCPU, 0,5 Go, `min-replicas 0` / `max-replicas 1` pour consommer le moins de crédit possible.

Commande pour tout (re)déployer :

```bash
./scripts/deploy.sh all        # infra + images + apps
./scripts/deploy.sh status     # état des apps et URL publique
```

## Réseau : comment le navigateur arrive jusqu'au backend

```
Navigateur ──HTTPS──► quiz-frontend (Nginx, ingress externe)
                          │  /api/*, /health
                          ▼
                      http://quiz-backend  (ingress interne, pas accessible depuis Internet)
                          │
                          ▼
                      Neon PostgreSQL (TLS)   ← J5
```

- Le frontend appelle l'API en **chemin relatif** (`/api/...`). C'est donc Nginx qui doit relayer vers le backend, comme en local.
- En local le backend s'appelle `backend:3007`, sur Azure il s'appelle `quiz-backend` (port 80 côté environnement). On a transformé `nginx.conf` en modèle (`nginx/templates/default.conf.template`) avec une variable `BACKEND_HOST`, remplacée au démarrage du conteneur par `envsubst` :
  - Compose : `BACKEND_HOST=backend:3007`
  - Azure : `BACKEND_HOST=quiz-backend`
- On envoie aussi `Host: quiz-backend` : le routeur interne d'Azure (Envoy) choisit l'app selon le nom d'hôte.
- Le backend en **ingress interne** n'a pas d'URL publique : on ne peut l'atteindre qu'en passant par le frontend. Moins de surface d'attaque.

## Vérification `/health`

`GET https://<url-frontend>/health` → **HTTP 200** `{"status":"ok"}` (capture `preuves/J4/health-http-200.png`). L'en-tête `x-powered-by: Express` prouve que la réponse vient bien du backend, relayée par Nginx.

Comme on l'avait vu en J1, `/health` ne touche pas à la base : le backend démarre même avec une `DATABASE_URL` factice (c'était le cas avant J5). Donc `/health` = 200 prouve que les conteneurs et le réseau marchent, **pas** que la base marche (c'est J5 qui le prouve).

## Révisions

Chaque `az containerapp update` (nouvelle image ou nouvelle variable) crée une **nouvelle révision** de l'app. Mode « single revision » : la nouvelle révision prend tout le trafic, l'ancienne est désactivée. Pour voir l'historique :

```bash
az containerapp revision list -n quiz-backend -g rg-quiz-app -o table
```

C'est ce qu'on utilise en J6 pour prouver que le déploiement automatique a bien mis à jour les apps.

## Ce qu'on retient

- Sans l'option `--environment-mode WorkloadProfiles`, Azure CLI crée maintenant un environnement « Express » qui ne permet pas l'appel interne `http://quiz-backend`. On a perdu du temps là-dessus.
- Le quota étudiant bloquait la création d'environnement en `germanywestcentral` : il faut lire le message d'erreur et changer de région, ce n'est pas notre script qui est faux.
- Identité managée + `AcrPull` = pas de mot de passe de registre à stocker nulle part.
- `min-replicas 0` = démarrage à froid de 10 à 30 s après une pause. Avant la démo, ouvrir l'URL un peu avant.

## Domaine personnalisé : g09.labformation.fr

Le frontend est publié sur **https://g09.labformation.fr** avec un **certificat TLS managé** par Azure (émis par DigiCert/GeoTrust, renouvelé automatiquement).

1. Identifiant de vérification de l'environnement : `az containerapp show -n quiz-frontend -g rg-quiz-app --query properties.customDomainVerificationId -o tsv`
2. Enregistrements DNS ajoutés par le formateur (zone gérée par lui) :
   - `CNAME g09` → `quiz-frontend.<…>.switzerlandnorth.azurecontainerapps.io`
   - `TXT asuid.g09` → identifiant de vérification (prouve que le domaine est bien rattaché à notre environnement)
3. Liaison et certificat :
   ```bash
   az containerapp hostname add  --hostname g09.labformation.fr -n quiz-frontend -g rg-quiz-app
   az containerapp hostname bind --hostname g09.labformation.fr -n quiz-frontend -g rg-quiz-app \
     --environment cae-quiz-app --validation-method CNAME
   ```
   `bindingType: SniEnabled` : le certificat est attaché (SNI = le serveur choisit le certificat selon le nom demandé).

Seul le frontend a un domaine : le backend reste en ingress interne, joint par Nginx via `http://quiz-backend`.
Preuve : [`preuves/J4/domaine-g09-labformation.txt`](../preuves/J4/domaine-g09-labformation.txt).
