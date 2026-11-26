# J3 — Azure CLI et Azure Container Registry

## Vérifications préalables (J0)

```bash
az login
az account show --query "{nom:name, etat:state}" -o table   # Azure for Students / Enabled
az policy assignment list --query "[].parameters.listOfAllowedLocations.value" -o tsv
```
Régions autorisées par l'abonnement : `switzerlandnorth`, `germanywestcentral`, `spaincentral`, `austriaeast`, `denmarkeast`.
**Choix : `germanywestcentral`** (Francfort) — la plus proche de Paris, ACR et Container Apps disponibles.

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
- **`--admin-enabled false`** : pas de couple identifiant/mot de passe partagé pour le registre. Docker se connecte avec `az acr login` (jeton Azure AD temporaire lié au compte connecté) ; les Container Apps tireront les images via une **identité managée** avec le rôle `AcrPull` (J4).
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
