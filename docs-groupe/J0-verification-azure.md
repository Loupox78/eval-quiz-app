# J0 — Vérification préalable de l'abonnement Azure

Vérification du 2026-11-26 avec **Azure CLI 2.93.0**.

## Commandes utilisées

```bash
az login                                   # connexion (navigateur), abonnement "Azure for Students"
az account show -o table                   # abonnement actif ?
az role assignment list --assignee <mon-id> --all -o table   # quels droits ?
az policy assignment list -o table         # restrictions imposées par l'école
az provider register -n Microsoft.ContainerRegistry --wait
az provider register -n Microsoft.App --wait
az provider register -n Microsoft.OperationalInsights --wait
```

## Constats

| Point vérifié | Résultat |
|---|---|
| Abonnement | `Azure for Students`, état **Enabled** |
| Droits | **Owner** sur l'abonnement → création de ressources et d'identités possible |
| Restriction de régions | Policy **« Allowed resource deployment regions »** : seules `polandcentral`, `italynorth`, `norwayeast`, `germanywestcentral`, `belgiumcentral` sont autorisées. **France Central et West Europe sont refusées.** |
| ACR (`Microsoft.ContainerRegistry`) | Fournisseur enregistré ; disponible dans les 5 régions autorisées |
| Container Apps (`Microsoft.App`) | Fournisseur enregistré ; disponible dans les 5 régions autorisées |
| Logs (`Microsoft.OperationalInsights`) | Fournisseur enregistré (requis par l'environnement Container Apps) |

## Décisions

- **Région retenue : `germanywestcentral`** (autorisée, la plus proche de la France parmi les régions permises, ACR et Container Apps disponibles). Toutes les ressources du projet y seront créées.
- **ACR en SKU Basic** (le moins cher) et Container Apps en mode consommation avec `min-replicas 0` quand c'est possible, pour économiser les crédits étudiants.
- Supprimer les ressources inutilisées après sauvegarde des preuves (`scripts/destroy.sh`).

## Points à surveiller

- **Crédits restants** : à vérifier sur https://www.microsoftazuresponsorships.com/balance (non consultable via Azure CLI).
- Toute création dans une région non listée échouera avec une erreur `RequestDisallowedByPolicy` : ce n'est pas un bug de nos scripts.
