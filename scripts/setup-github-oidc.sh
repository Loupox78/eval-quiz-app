#!/usr/bin/env bash
# J6 — Autorise GitHub Actions (branche main du fork) à déployer sur Azure, SANS mot de passe.
#
# Principe (OIDC / fédération d'identité) :
#   - une identité managée Azure "id-quiz-github" est créée dans le groupe de ressources ;
#   - on déclare qu'elle fait confiance aux jetons OIDC émis par GitHub pour
#     repo:<GITHUB_REPO>:ref:refs/heads/main (et rien d'autre) ;
#   - à chaque exécution, GitHub fournit un jeton éphémère que azure/login échange
#     contre un accès Azure temporaire. Aucun secret longue durée n'est stocké.
#
# Droits accordés (moindre privilège) :
#   - AcrPush sur l'ACR       : publier les images
#   - Contributor sur le RG   : mettre à jour les Container Apps du groupe uniquement
#
# Usage : ./scripts/setup-github-oidc.sh
# Affiche les 3 valeurs à enregistrer dans GitHub (Settings > Secrets and variables > Actions).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

GITHUB_REPO="${GITHUB_REPO:-Loupox78/eval-quiz-app}"   # sensible à la casse
GH_IDENTITY="${GH_IDENTITY:-id-quiz-github}"

az account show -o none 2>/dev/null || { echo "Non connecté : lancez 'az login'" >&2; exit 1; }

echo "==> Identité managée $GH_IDENTITY"
az identity show -n "$GH_IDENTITY" -g "$RG" -o none 2>/dev/null \
  || az identity create -n "$GH_IDENTITY" -g "$RG" -l "$LOCATION" -o none

CLIENT_ID="$(az identity show -n "$GH_IDENTITY" -g "$RG" --query clientId -o tsv)"
PRINCIPAL_ID="$(az identity show -n "$GH_IDENTITY" -g "$RG" --query principalId -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
RG_ID="$(az group show -n "$RG" --query id -o tsv)"
ACR_ID="$(az acr show -n "$ACR_NAME" --query id -o tsv)"

# GitHub émet désormais un "subject" OIDC contenant aussi les identifiants numériques
# (immuables) du propriétaire et du dépôt :
#   repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/main
# Ces identifiants empêchent qu'un dépôt recréé plus tard sous le même nom hérite de l'accès.
# Valeurs pour Loupox78/eval-quiz-app (API GitHub : GET /repos/Loupox78/eval-quiz-app -> owner.id, id) :
GITHUB_OWNER_ID="${GITHUB_OWNER_ID:-150783612}"
GITHUB_REPO_ID="${GITHUB_REPO_ID:-1472881647}"
OIDC_SUBJECT="repo:${GITHUB_REPO%%/*}@${GITHUB_OWNER_ID}/${GITHUB_REPO##*/}@${GITHUB_REPO_ID}:ref:refs/heads/main"

echo "==> Fédération : jetons GitHub de $OIDC_SUBJECT"
if ! az identity federated-credential show -n github-main-ids --identity-name "$GH_IDENTITY" -g "$RG" -o none 2>/dev/null; then
  az identity federated-credential create -n github-main-ids --identity-name "$GH_IDENTITY" -g "$RG" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "$OIDC_SUBJECT" \
    --audiences "api://AzureADTokenExchange" -o none
fi

assign() { # rôle, scope
  if [[ -z "$(az role assignment list --assignee "$PRINCIPAL_ID" --scope "$2" --role "$1" --query '[].id' -o tsv)" ]]; then
    for _ in 1 2 3 4 5 6; do
      az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
        --role "$1" --scope "$2" -o none 2>/dev/null && return 0
      echo "  identité pas encore propagée, nouvel essai dans 10 s..."; sleep 10
    done
    echo "Échec de l'attribution du rôle $1" >&2; exit 1
  fi
}
echo "==> Rôle AcrPush sur l'ACR"; assign AcrPush "$ACR_ID"
echo "==> Rôle Contributor sur le groupe $RG"; assign Contributor "$RG_ID"

cat <<OUT

À enregistrer dans GitHub : https://github.com/$GITHUB_REPO/settings/secrets/actions
(onglet Secrets > New repository secret). Ce sont des identifiants, pas des mots de passe :
ils ne donnent aucun accès sans un jeton OIDC émis par GitHub pour la branche main.

  AZURE_CLIENT_ID        $CLIENT_ID
  AZURE_TENANT_ID        $TENANT_ID
  AZURE_SUBSCRIPTION_ID  $SUBSCRIPTION_ID
OUT
