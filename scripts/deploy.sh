#!/usr/bin/env bash
# Déploiement Azure de Quiz App avec Azure CLI.
#
# Prérequis :
#   - Azure CLI installé et connecté : az login
#   - Docker démarré (les images sont construites en local)
#   - Lancer depuis la racine du dépôt : ./scripts/deploy.sh
#
# Étapes actuelles (J3) :
#   1. Groupe de ressources
#   2. Azure Container Registry (ACR)
#   3. Build des images backend/frontend, tag = commit Git, push dans l'ACR
# Les étapes Container Apps (J4) seront ajoutées ensuite.
#
# Le script est idempotent : le relancer ne recrée pas ce qui existe déjà.

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

echo "==> Abonnement : $(az account show --query name -o tsv)"
echo "==> Région : $LOCATION | Groupe : $RESOURCE_GROUP | ACR : $ACR_NAME | Tag : $IMAGE_TAG"

# 1. Groupe de ressources (conteneur logique de toutes les ressources du projet)
echo "==> [1/3] Groupe de ressources"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

# 2. Registre d'images privé
echo "==> [2/3] Azure Container Registry"
if ! az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  az acr create \
    --name "$ACR_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku "$ACR_SKU" \
    --admin-enabled false \
    --output none
fi
ACR_SERVER="$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)"
echo "    Registre : $ACR_SERVER"

# 3. Build + push. az acr login donne à Docker un jeton temporaire (pas de mot de passe stocké)
echo "==> [3/3] Build et push des images"
az acr login --name "$ACR_NAME"

docker build --pull -t "$ACR_SERVER/$BACKEND_IMAGE:$IMAGE_TAG" ./backend
docker build --pull -t "$ACR_SERVER/$FRONTEND_IMAGE:$IMAGE_TAG" .

docker push "$ACR_SERVER/$BACKEND_IMAGE:$IMAGE_TAG"
docker push "$ACR_SERVER/$FRONTEND_IMAGE:$IMAGE_TAG"

echo "==> Images publiées :"
echo "    $ACR_SERVER/$BACKEND_IMAGE:$IMAGE_TAG"
echo "    $ACR_SERVER/$FRONTEND_IMAGE:$IMAGE_TAG"
