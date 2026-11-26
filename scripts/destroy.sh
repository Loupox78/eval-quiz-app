#!/usr/bin/env bash
# Suppression de TOUTES les ressources Azure du projet (opération irréversible).
#
# Supprime le groupe de ressources, donc tout ce qu'il contient :
# ACR (et ses images), environnement et applications Container Apps, logs.
# La base Neon (externe à Azure) n'est PAS concernée.
#
# Avant de lancer : sauvegarder les preuves (captures, sorties de commandes) et
# avoir l'accord du formateur.
#
# Usage : ./scripts/destroy.sh          (demande une confirmation)
#         ./scripts/destroy.sh --yes    (sans confirmation, ex. CI)

set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

if ! az group exists --name "$RESOURCE_GROUP" | grep -q true; then
  echo "Le groupe $RESOURCE_GROUP n'existe pas : rien à supprimer."
  exit 0
fi

echo "Ressources qui vont être supprimées :"
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{nom:name, type:type}" -o table

if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Supprimer définitivement le groupe '$RESOURCE_GROUP' ? Tapez son nom pour confirmer : " answer
  if [[ "$answer" != "$RESOURCE_GROUP" ]]; then
    echo "Annulé."
    exit 1
  fi
fi

az group delete --name "$RESOURCE_GROUP" --yes
echo "Groupe $RESOURCE_GROUP supprimé."
