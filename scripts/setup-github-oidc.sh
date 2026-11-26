#!/usr/bin/env bash
# Prépare l'authentification de GitHub Actions sur Azure, SANS mot de passe (OIDC).
# À lancer UNE fois, par le propriétaire de l'abonnement et admin du dépôt GitHub,
# après ./scripts/deploy.sh all (le groupe, l'ACR et les Container Apps doivent exister).
#
# Ce que fait le script :
#   1. crée une identité managée "id-quiz-github" dans le groupe de ressources
#   2. lui fait confiance pour les jetons OIDC émis par GitHub, uniquement pour
#      les workflows qui tournent sur la branche main de ce dépôt
#   3. lui donne le minimum de droits :
#        - Reader      sur le groupe de ressources (lire l'ACR, l'environnement, les apps)
#        - AcrPush     sur l'ACR (pousser les images)
#        - Contributor sur les 2 Container Apps seulement (créer des révisions)
#   4. enregistre AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_SUBSCRIPTION_ID en secrets GitHub
#      (avec gh si disponible, sinon les affiche pour les saisir à la main)
#
# Usage : ./scripts/setup-github-oidc.sh [owner/repo]   (défaut : Loupox78/eval-quiz-app)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

REPO="${1:-Loupox78/eval-quiz-app}"
GITHUB_IDENTITY="${GITHUB_IDENTITY:-id-quiz-github}"

az account show -o none 2>/dev/null || { echo "Non connecté : lancez 'az login'" >&2; exit 1; }

echo "==> Identité managée $GITHUB_IDENTITY"
az identity show -n "$GITHUB_IDENTITY" -g "$RG" -o none 2>/dev/null \
  || az identity create -n "$GITHUB_IDENTITY" -g "$RG" -l "$LOCATION" -o none

CLIENT_ID="$(az identity show -n "$GITHUB_IDENTITY" -g "$RG" --query clientId -o tsv)"
PRINCIPAL_ID="$(az identity show -n "$GITHUB_IDENTITY" -g "$RG" --query principalId -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

echo "==> Confiance OIDC : workflows de $REPO sur la branche main uniquement"
if ! az identity federated-credential show -n github-main --identity-name "$GITHUB_IDENTITY" -g "$RG" -o none 2>/dev/null; then
  az identity federated-credential create -n github-main \
    --identity-name "$GITHUB_IDENTITY" -g "$RG" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "repo:${REPO}:ref:refs/heads/main" \
    --audiences "api://AzureADTokenExchange" -o none
fi

assign() { # rôle, portée
  if [[ -z "$(az role assignment list --assignee "$PRINCIPAL_ID" --role "$1" --scope "$2" --query '[].id' -o tsv)" ]]; then
    for i in 1 2 3 4 5 6; do
      az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
        --role "$1" --scope "$2" -o none 2>/dev/null && return 0
      echo "   identité pas encore propagée, nouvel essai dans 10 s..."; sleep 10
    done
    echo "Impossible d'attribuer $1" >&2; exit 1
  fi
}

echo "==> Droits minimum"
RG_ID="$(az group show -n "$RG" --query id -o tsv)"
ACR_ID="$(az acr show -n "$ACR_NAME" --query id -o tsv)"
assign Reader "$RG_ID"
assign AcrPush "$ACR_ID"
for app in "$BACKEND_APP" "$FRONTEND_APP"; do
  assign Contributor "$(az containerapp show -n "$app" -g "$RG" --query id -o tsv)"
done

echo "==> Secrets GitHub"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  gh secret set AZURE_CLIENT_ID       -R "$REPO" -b "$CLIENT_ID"
  gh secret set AZURE_TENANT_ID       -R "$REPO" -b "$TENANT_ID"
  gh secret set AZURE_SUBSCRIPTION_ID -R "$REPO" -b "$SUBSCRIPTION_ID"
  echo "Secrets enregistrés dans $REPO."
else
  echo "gh indisponible : créez ces 3 secrets dans GitHub > Settings > Secrets and variables > Actions"
  echo "  AZURE_CLIENT_ID       = $CLIENT_ID"
  echo "  AZURE_TENANT_ID       = $TENANT_ID"
  echo "  AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
fi
echo "Terminé. Test : GitHub > Actions > Deploy > Run workflow."
