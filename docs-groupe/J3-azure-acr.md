# J3 — Azure CLI et Azure Container Registry

## Vérifications préalables (J0)

```bash
az login
az account show --query "{nom:name, etat:state}" -o table   # Azure for Students / Enabled
az policy assignment list --query "[].parameters.listOfAllowedLocations.value" -o tsv
```
Régions autorisées par l'abonnement : `switzerlandnorth`, `germanywestcentral`, `spaincentral`, `austriaeast`, `denmarkeast`.
Premier choix : `germanywestcentral` (Francfort, la plus proche). La création d'environnement Container Apps y étant refusée pour ce compte (voir incidents ci-dessous), **toutes les ressources sont finalement en `switzerlandnorth` (Zurich)** : ACR, identité et Container Apps dans la même région (pas de transfert d'images inter-régions).

## Ressources créées

| Ressource | Nom | Rôle |
|---|---|---|
| Groupe de ressources | `rg-quiz-app` | Regroupe tout le projet ; sa suppression nettoie tout (`scripts/destroy.sh`) |
| Azure Container Registry | `acrquizloupox78` (SKU Basic) | Registre privé des images ; compte admin **désactivé** |

Paramètres centralisés dans [`scripts/config.sh`](../scripts/config.sh) (aucun secret).

## Commandes

```bash
./scripts/deploy.sh infra    # provider register + az group create + az acr create
./scripts/deploy.sh images   # az acr login + docker buildx --platform linux/amd64 --push
./scripts/deploy.sh status
az acr repository list -n acrquizloupox78 -o table
az acr repository show-tags -n acrquizloupox78 --repository quiz-backend -o table
```

## Choix techniques

- **Script idempotent** : chaque ressource est testée (`az ... show`) avant création → le script peut être relancé sans erreur.
- **`az provider register`** : un abonnement neuf n'a pas les fournisseurs `Microsoft.ContainerRegistry`, `Microsoft.App`, `Microsoft.OperationalInsights` activés.
- **SKU Basic** : le moins cher, suffisant pour l'exercice.
- **`--admin-enabled false`** : pas de couple identifiant/mot de passe partagé pour le registre. Docker se connecte avec `az acr login` (jeton Azure AD temporaire lié au compte connecté) ; les Container Apps tirent les images via l'**identité managée user-assigned `id-quiz-acrpull`**, qui n'a que le rôle `AcrPull` (lecture) sur l'ACR — principe du moindre privilège.
- **Tags traçables** : chaque image reçoit le **hash court du commit Git** (`git rev-parse --short HEAD`), plus `latest`. On sait exactement quel code tourne.
- **`--platform linux/amd64`** : un Mac Apple Silicon construit par défaut des images arm64, qu'Azure ne peut pas exécuter. `docker buildx` produit une image amd64 par émulation.

## Préparation de J4 : adresse du backend configurable

En local, Nginx joint le backend par le nom de service Compose `backend:3007`. Sur Azure Container Apps, le backend s'appelle `quiz-backend` et est joignable en interne sur le port 80.
→ `nginx/nginx.conf` est remplacé par le modèle [`nginx/templates/default.conf.template`](../nginx/templates/default.conf.template). Au démarrage, l'image Nginx remplace `${BACKEND_HOST}` par la valeur de la variable d'environnement (`envsubst`) :
- Compose : `BACKEND_HOST=backend:3007`
- Azure : `BACKEND_HOST=quiz-backend`

L'en-tête `Host` envoyé au backend vaut aussi `${BACKEND_HOST}` : sur Azure, le routeur interne (Envoy) aiguille les requêtes selon ce nom d'hôte.

## Coûts

ACR Basic : environ 5 $/mois, prélevés sur le crédit Azure for Students. Supprimer avec `./scripts/destroy.sh` après validation et accord du formateur.

## Questions probables à l'oral

- *Pourquoi un registre ?* → Azure Container Apps doit télécharger les images depuis un registre accessible ; l'ACR est privé et dans le même compte.
- *Pourquoi ne pas utiliser `latest` seulement ?* → `latest` change à chaque push, impossible de savoir quelle version tourne ni de revenir en arrière.
- *Pourquoi linux/amd64 ?* → architecture des serveurs Azure ; une image arm64 échouerait au démarrage (`exec format error`).
- *Comment Docker s'authentifie sur l'ACR ?* → `az acr login` utilise la session `az login` pour obtenir un jeton temporaire ; aucun mot de passe stocké.

## Incident : environnement créé en mode « Express »

Premier lancement de `./scripts/deploy.sh apps` :
```
(ExpressAllowInsecureNotSupported) Allow Insecure is not supported for container app 'quiz-backend' on express environments.
```
**Diagnostic** : `az containerapp env show ... --query properties.environmentMode` → `Express`. Sans option, Azure CLI 2.93 crée un environnement **Express** (mode simplifié récent). D'après la documentation Microsoft, Express n'accepte que l'ingress HTTPS, ne fournit **pas de découverte de service interne** (appel `http://quiz-backend` impossible) et ne supporte **pas l'identité managée système**.

**Correction** : création explicite en mode standard `--environment-mode WorkloadProfiles` (profil Consumption, facturation à l'usage). Le script refuse désormais de continuer sur un environnement Express et indique la commande de suppression.

## Incident : quota d'environnements dans la région

Après suppression de l'environnement Express, recréation refusée :
```
(MaxNumberOfEnvironmentsInSubExceeded) The subscription '…' cannot create Container App Environments in region 'Germany West Central'. Please try another region.
```
**Diagnostic** : `az containerapp env list -o table` → aucun environnement existant ; la limite vient de l'abonnement Azure for Students pour cette région.
**Correction** : nouvelle variable `ACA_LOCATION` dans `scripts/config.sh` (défaut `switzerlandnorth`, région autorisée). L'ACR reste en `germanywestcentral` : un environnement peut tirer des images d'un registre situé dans une autre région (léger surcoût de transfert, négligeable ici).

## Incident : `UNAUTHORIZED` au tirage de l'image

```
Field 'template.containers.quiz-backend.image' is invalid ... UNAUTHORIZED: authentication required
```
**Causes** : (1) une première création du backend avec `--registry-identity system` a échoué (`InternalServerError`) en laissant une app sans configuration de registre ; (2) le tag demandé (`git rev-parse --short HEAD`) ne correspondait plus aux images poussées, car de nouveaux commits avaient été faits entre-temps.
**Corrections** :
- identité **user-assigned** `id-quiz-acrpull` créée à l'étape `infra`, avec rôle `AcrPull` sur l'ACR, *avant* les apps → plus de dépendance à la création d'identité pendant `containerapp create` ; les apps existantes sont reconfigurées (`containerapp identity assign` + `containerapp registry set`) ;
- vérification que `image:TAG` existe dans l'ACR avant le déploiement, avec message explicite.

## Décision finale : tout en Suisse

Pour garder toutes les ressources dans une seule région, l'ACR et l'identité créés à Francfort ont été supprimés puis recréés en `switzerlandnorth` (`LOCATION` dans `scripts/config.sh`). Le groupe de ressources `rg-quiz-app` reste déclaré en `germanywestcentral` : la région d'un groupe ne concerne que ses métadonnées et ne peut pas être changée ; elle n'impose rien aux ressources qu'il contient.
