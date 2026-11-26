#!/usr/bin/env bash
# Suppression de TOUTES les ressources Azure du projet (groupe de ressources entier).
# Opération irréversible : ACR + images, environnement, Container Apps, logs.
# À lancer seulement après avoir sauvegardé les preuves et obtenu l'accord du formateur.
#
# Usage : ./scripts/destroy.sh          (demande confirmation)
#         ./scripts/destroy.sh --yes    (sans confirmation)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

az account show -o none 2>/dev/null || { echo "Non connecté : lancez 'az login'" >&2; exit 1; }

if ! az group show -n "$RG" -o none 2>/dev/null; then
  echo "Le groupe de ressources $RG n'existe pas : rien à supprimer."
  exit 0
fi

echo "Ressources qui vont être supprimées :"
az resource list -g "$RG" --query "[].{Nom:name, Type:type}" -o table

if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Tapez le nom du groupe ($RG) pour confirmer : " answer
  [[ "$answer" == "$RG" ]] || { echo "Annulé."; exit 1; }
fi

az group delete -n "$RG" --yes --no-wait
echo "Suppression de $RG lancée (quelques minutes). Suivi : az group show -n $RG"
