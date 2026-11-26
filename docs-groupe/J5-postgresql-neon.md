# J5 — PostgreSQL cloud avec Neon

## Pourquoi une base externe managée

Sur Azure Container Apps, les conteneurs sont **jetables** (recréés à chaque déploiement, redémarrage ou mise à l'échelle). Une base PostgreSQL dans un conteneur y perdrait ses données et nous obligerait à gérer sauvegardes et correctifs. On utilise donc un **PostgreSQL managé externe : Neon** (offre gratuite, recommandée par la consigne). Azure Database for PostgreSQL aurait été possible mais payant pour un compte étudiant.

En local, rien ne change : PostgreSQL reste dans Docker Compose avec le volume `pgdata`. Le backend est **identique** dans les deux cas ; seule la variable `DATABASE_URL` change.

```
Local : navigateur → frontend (Nginx) → backend → conteneur postgres + volume pgdata
Azure : navigateur → frontend (ACA, externe) → backend (ACA, interne) → Neon (AWS eu-central-1, TLS)
```

## Mise en place

1. Projet Neon `quiz-app`, région **AWS Europe Central 1 (Frankfurt)** — la plus proche des Container Apps en Suisse (`switzerlandnorth`).
2. **Initialisation du schéma** : contenu de `database/init.sql` exécuté **une seule fois** dans le SQL Editor de Neon. Le script n'est pas idempotent (`CREATE TABLE` sans `IF NOT EXISTS`) : le relancer échouerait sur les tables existantes. Vérification :
   ```sql
   SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
   -- users, quiz_results, answers
   ```
3. **Chaîne de connexion** stockée uniquement dans `.env.azure` (ignoré par Git), au format :
   ```
   DATABASE_URL="postgresql://<user>:<mot_de_passe>@<hôte>-pooler.<région>.aws.neon.tech/neondb?sslmode=verify-full"
   ```
4. Déploiement : `TAG=d063dd1 ./scripts/deploy.sh apps` (images déjà présentes dans l'ACR, code applicatif inchangé).

## TLS

- Neon refuse les connexions non chiffrées.
- `sslmode=verify-full` : connexion chiffrée **et** vérification que le certificat correspond bien à l'hôte Neon (protection contre l'usurpation / attaque de l'intermédiaire). Neon fournit `sslmode=require` par défaut ; le pilote `pg` 8.23 traite déjà `require` comme `verify-full` (avertissement de sécurité), on l'écrit explicitement pour rester correct lors du passage à `pg` 9.
- Le paramètre `channel_binding=require` proposé par Neon a été retiré : `pg` ne le lit pas depuis l'URL (il l'ignore).

## Gestion du secret

- `DATABASE_URL` contient le mot de passe → **secret Container Apps** `database-url`, injecté via `secretref:database-url`. `az containerapp secret list` n'affiche que les noms ; la variable d'environnement ne contient pas la valeur.
- Un secret modifié n'est lu qu'au démarrage du conteneur : `scripts/deploy.sh` redémarre désormais la révision active du backend après `az containerapp secret set`.
- Aucune chaîne réelle n'est commitée (vérifié sur tout l'historique Git).

## Persistance

Inscription + quiz sur l'URL Azure → ligne visible dans Neon. Puis `az containerapp revision restart` du backend → le résultat est toujours renvoyé par `/api/admin/results`. Les données vivent dans Neon, indépendamment du cycle de vie des conteneurs.

## Observation : démarrage à froid

Les Container Apps sont en `--min-replicas 0` (*scale to zero*) pour économiser le crédit étudiant : après une période sans trafic, la première requête prend 10 à 30 s le temps de redémarrer les conteneurs. Avant une démonstration, ouvrir l'URL 1 à 2 minutes à l'avance.

## Questions probables à l'oral

- *Pourquoi pas Postgres dans un conteneur sur Azure ?* → conteneurs jetables, pas de volume persistant simple, sauvegardes à gérer soi-même.
- *Comment le schéma est créé en cloud ?* → `init.sql` exécuté une fois dans Neon ; en local, automatiquement par l'image postgres au premier démarrage du volume.
- *Différence `require` / `verify-full` ?* → `require` chiffre sans vérifier l'identité du serveur (sémantique libpq) ; `verify-full` vérifie aussi le certificat et le nom d'hôte.
- *Où est le mot de passe de la base ?* → dans le secret Container Apps et dans `.env.azure` local (non versionné), nulle part dans Git.
- *Que se passe-t-il si on redéploie ?* → nouvelle révision, nouveaux conteneurs, mêmes données (Neon).
