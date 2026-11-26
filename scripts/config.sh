#!/usr/bin/env bash
# Paramètres communs aux scripts Azure (aucun secret ici).
# Chaque valeur peut être surchargée par une variable d'environnement :
#   ex. LOCATION=spaincentral ./scripts/deploy.sh infra

# Groupe de ressources : "dossier" qui contient toutes les ressources du projet
RG="${RG:-rg-quiz-app}"

# Région : doit faire partie des régions autorisées par l'abonnement Azure for Students
#   az policy assignment list --query "[].parameters.listOfAllowedLocations.value" -o tsv
LOCATION="${LOCATION:-germanywestcentral}"

# Nom de l'ACR : unique au monde, 5 à 50 caractères, lettres minuscules et chiffres uniquement
ACR_NAME="${ACR_NAME:-acrquizloupox78}"

# Environnement Azure Container Apps (réseau + logs partagés par les deux applications)
ACA_ENV="${ACA_ENV:-cae-quiz-app}"

# Noms des Container Apps. Le frontend joint le backend par son nom (http://quiz-backend)
BACKEND_APP="${BACKEND_APP:-quiz-backend}"
FRONTEND_APP="${FRONTEND_APP:-quiz-frontend}"

# Noms des images dans l'ACR
BACKEND_IMAGE="${BACKEND_IMAGE:-quiz-backend}"
FRONTEND_IMAGE="${FRONTEND_IMAGE:-quiz-frontend}"

# Tag traçable : hash court du commit Git (ex. a67d1aa)
TAG="${TAG:-$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M)}"

# Plateforme des images : Azure exécute des conteneurs linux/amd64
# (un Mac Apple Silicon construit en arm64 par défaut)
PLATFORM="${PLATFORM:-linux/amd64}"
