# J3 — Azure CLI et Azure Container Registry (ACR)

Réalisé le 2026-11-26 avec Azure CLI 2.93.0, abonnement Azure for Students.
Preuves : [`preuves/J3/ressources-acr.txt`](../preuves/J3/ressources-acr.txt) et [`preuves/J3/sortie-deploy.txt`](../preuves/J3/sortie-deploy.txt).

## Ressources créées

| Ressource | Nom | Détail |
|---|---|---|
| Groupe de ressources | `rg-eval-quiz` | `germanywestcentral` (région imposée par la policy de l'école, voir [J0](J0-verification-azure.md)) |
| Azure Container Registry | `acrevalquizmems` | SKU **Basic** (le moins cher), serveur `acrevalquizmems.azurecr.io`, **compte admin désactivé** |
| Image backend | `quiz-backend:2353651` | digest `sha256:6cf9e8df…` |
| Image frontend | `quiz-frontend:2353651` | digest `sha256:0e469626…` |

## Scripts

| Fichier | Rôle |
|---|---|
| [`scripts/config.sh`](../scripts/config.sh) | Variables communes (région, groupe, nom de l'ACR, tag). Aucun secret. Chaque valeur peut être surchargée par une variable d'environnement. |
| [`scripts/deploy.sh`](../scripts/deploy.sh) | Crée le groupe et l'ACR s'ils n'existent pas, construit les 2 images et les pousse. **Idempotent** : on peut le relancer sans erreur. |
| [`scripts/destroy.sh`](../scripts/destroy.sh) | Supprime le groupe de ressources et tout son contenu, après confirmation (taper le nom du groupe). |

```bash
az login                 # MFA obligatoire pour créer des ressources (voir plus bas)
./scripts/deploy.sh      # depuis la racine du dépôt, Docker démarré
./scripts/destroy.sh     # nettoyage, après sauvegarde des preuves et accord du formateur
```

## Choix techniques

- **Tag = hash court du commit Git** (`2353651`) plutôt que `latest` : on sait exactement quel code tourne. Si des fichiers ne sont pas commités, le tag reçoit le suffixe `-dirty` pour le signaler.
- **Digest** (`sha256:…`) : identifiant immuable du contenu. Un tag peut être déplacé, un digest non.
- **`--admin-enabled false`** : pas de couple identifiant/mot de passe permanent sur le registre. `az acr login` fournit à Docker un **jeton temporaire** basé sur la connexion Azure ; en J4, Container Apps tirera les images avec une **identité managée**, et en J6 la CI avec une identité de service.
- **`docker build --pull`** : récupère toujours la dernière version des images de base (leçon de J2 : une image en cache contenait 236 vulnérabilités de plus).
- **Build local puis push** plutôt que `az acr build` : réutilise exactement les Dockerfiles testés en J1/J2.
- **`.gitattributes`** force les fins de ligne LF sur les `*.sh` : avec des fins de ligne Windows (CRLF), bash échoue sous Linux (CI GitHub Actions).

Les entrées sans tag visibles dans `az acr manifest list-metadata` sont normales : Docker Desktop (BuildKit) publie un **index** multi-plateforme qui pointe vers le manifeste de l'image et vers un manifeste d'**attestation** (provenance du build).

## Incident rencontré : MFA obligatoire

Premier lancement : erreur `AADSTS50076 … you must use multi-factor authentication`. Le tenant de l'école impose la MFA pour toute écriture sur Azure Resource Manager, et le premier `az login` (passé par le gestionnaire de comptes Windows, WAM) avait réutilisé une session existante sans MFA.

Correction :

```bash
az config set core.enable_broker_on_windows=false   # connexion via le navigateur au lieu de WAM
az logout
az login --tenant <tenant-id> --scope "https://management.core.windows.net//.default" --claims-challenge <valeur fournie par l'erreur>
```

À anticiper pour la CI (J6) : une identité de service (OIDC / principal de service) n'est pas soumise à la MFA utilisateur.

## Coûts

ACR Basic ≈ 5 $/mois (facturé au jour). Rien d'autre n'est facturé à ce stade. Supprimer avec `scripts/destroy.sh` dès que les jalons sont validés.
