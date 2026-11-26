#!/usr/bin/env bash
# Configuration commune aux scripts Azure. AUCUN secret ici.
# Chaque valeur peut être surchargée par une variable d'environnement :
#   ACR_NAME=monacr ./scripts/deploy.sh

# Région : la policy de l'école n'autorise que polandcentral, italynorth,
# norwayeast, germanywestcentral et belgiumcentral (voir docs-groupe/J0-verification-azure.md)
LOCATION="${LOCATION:-germanywestcentral}"

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-eval-quiz}"

# Nom d'ACR : unique dans tout Azure, 5-50 caractères, lettres minuscules et chiffres uniquement
ACR_NAME="${ACR_NAME:-acrevalquizmems}"
ACR_SKU="${ACR_SKU:-Basic}"

BACKEND_IMAGE="quiz-backend"
FRONTEND_IMAGE="quiz-frontend"

# Tag traçable : hash court du commit Git (+ "-dirty" si des fichiers ne sont pas commités)
if git rev-parse --git-dir >/dev/null 2>&1; then
  IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- || echo -dirty)}"
else
  IMAGE_TAG="${IMAGE_TAG:-manual}"
fi
