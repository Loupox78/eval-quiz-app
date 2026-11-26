# Quiz App — dépôt du groupe Loupox78 / Mems932

Fork de [`franklin-tutorials/eval-quiz-app`](https://github.com/franklin-tutorials/eval-quiz-app). Notre travail : conteneuriser Quiz App, sécuriser les images, la déployer sur Azure et automatiser les livraisons. **Le code de l'application n'a pas été modifié** (sauf une question de quiz pour la démo CI/CD).

La consigne d'origine du formateur est conservée plus bas, à partir de [« Consigne du formateur »](#consigne-du-formateur).

## Où en est chaque jalon

| Jalon | Documentation | Preuves | PR |
|---|---|---|---|
| J0 — Vérification Azure | [J0](docs-groupe/J0-verification-azure.md) | — | #3 |
| J1 — Conteneurisation locale | [J1](docs-groupe/J1-conteneurisation.md) | [preuves/J1](preuves/J1/) | #1, #3 |
| J2 — Sécurité des images (Trivy) | [J2](docs-groupe/J2-securite-trivy.md) | [preuves/J2](preuves/J2/) | #2, #5 |
| J3 — Azure CLI + ACR | [J3](docs-groupe/J3-azure-acr.md) | [preuves/J3](preuves/J3/) | #4 |
| J4 — Azure Container Apps | [J4](docs-groupe/J4-container-apps.md) | [preuves/J4](preuves/J4/) | #4 |
| J5 — PostgreSQL cloud (Neon) | [J5](docs-groupe/J5-postgresql-neon.md) | [preuves/J5](preuves/J5/) | #7 |
| J6 — CI/CD GitHub Actions | [J6](docs-groupe/J6-cicd.md) | [preuves/J6](preuves/J6/) | #9, démo d'échec #10 |

Schémas d'architecture (local, Azure, chaîne de livraison) : [docs-groupe/architecture.md](docs-groupe/architecture.md).

## Lancer le projet en local

Prérequis : Docker Desktop (ou Docker Engine + Compose v2), Git.

```bash
git clone https://github.com/Loupox78/eval-quiz-app.git
cd eval-quiz-app
cp .env.example .env          # puis changer les mots de passe dans .env (jamais commité)
docker compose up -d --build
```

- Quiz : http://localhost:8087
- Administration : http://localhost:8087/gestion-quiz (identifiants `ADMIN_USERNAME` / `ADMIN_PASSWORD` du `.env`)
- Santé : http://localhost:8087/health → `{"status":"ok"}`

Arrêter : `docker compose down` (garde les données). Tout effacer, base comprise : `docker compose down -v`.

> Attention : `POSTGRES_PASSWORD` n'est lu qu'à la **première** création du volume `pgdata`. Pour le changer ensuite, soit `ALTER USER` dans la base, soit `docker compose down -v` (perte des données).

## Déployer sur Azure

Prérequis : Azure CLI connecté (`az login`, MFA demandée par le tenant de l'école), Docker démarré, et un fichier `.env.azure` rempli à partir de [`.env.azure.example`](.env.azure.example) (jamais commité).

```bash
./scripts/deploy.sh all       # groupe + ACR + identité, build/push des images, Container Apps
./scripts/deploy.sh status    # état et URL publique
```

Les paramètres non secrets (région, noms des ressources) sont dans [`scripts/config.sh`](scripts/config.sh). Les régions autorisées dépendent de l'abonnement étudiant (voir J0 et J3).

Après fusion dans `main`, le workflow GitHub Actions `cd.yml` fait la même mise à jour automatiquement (voir [J6](docs-groupe/J6-cicd.md)).

## Nettoyer

```bash
./scripts/destroy.sh          # supprime le groupe de ressources (ACR, Container Apps, logs) après confirmation
```

À faire seulement après avoir sauvegardé les preuves et eu l'accord du formateur. La base Neon est à supprimer à part, dans la console Neon.

## Usage de l'IA

Outil : un assistant IA de code, utilisé dans le terminal.

- **Pour quoi** : explications de notions, premières versions de configurations qu'on a ensuite adaptées, aide au diagnostic des erreurs Azure et Trivy, relecture.
- **Vérification** : tout a été testé pour de vrai (Compose, `curl`, scans Trivy avant/après, déploiements Azure, Neon) et passe par la CI avant fusion. Chacun sait réexpliquer ce qu'il a poussé.
- **Secrets** : aucun mot de passe, chaîne de connexion ni clé n'est donné à l'IA ; les connexions (`az login`, `gh auth login`) sont faites par nous.

---

# Consigne du formateur

# Quiz App - Projet d'évaluation Conteneurisation

## Mission

Vous intégrez une équipe DevOps chargée de **conteneuriser, sécuriser et déployer** l'application **Quiz App** sur Microsoft Azure, puis d'automatiser ses livraisons.

Le **code applicatif est fourni**. Votre mission concerne la conteneurisation, l'exploitation, la sécurité et le déploiement ; **ne modifiez pas la logique métier**. Une modification ciblée d'une question de quiz présente dans le code servira à démontrer le processus de livraison.

L'application comporte un frontend, un backend et une base PostgreSQL. Elle peut utiliser un service d'envoi d'emails ; les fonctionnalités qui en dépendent doivent être configurées uniquement si les accès nécessaires sont fournis.

## Résultat attendu

1. Faire fonctionner Quiz App localement avec Docker, Docker Compose et PostgreSQL persistant.
2. Construire des images sécurisées, analyser les vulnérabilités et documenter les corrections.
3. Déployer les images via Azure Container Registry (ACR) sur Azure Container Apps avec Azure CLI.
4. Connecter le backend à un PostgreSQL externe (Neon recommandé, ou solution compatible).
5. Mettre en place une CI/CD avec **GitHub Actions (recommandé)** ou **GitLab CI/CD (autorisé)** : contrôles sur Pull/Merge Request, scan Trivy bloquant, puis publication et déploiement après fusion dans `main`.
6. Présenter le travail et les preuves de chaque jalon lors d'une soutenance.

Les jalons sont validés progressivement. Une difficulté sur PostgreSQL cloud n'annule pas les jalons déjà acquis et n'interdit pas de démontrer la partie CI/CD technique.

## Travail à partir du dépôt officiel

Le formateur publie le code de départ et les consignes sur la branche `main` de son dépôt **de référence**. **Chaque groupe crée un fork de ce dépôt sur GitHub**, puis travaille exclusivement dans son fork. Les branches `feature/*` et les Pull Requests doivent cibler **`main` du fork du groupe**, jamais `main` du formateur.

- Sur GitHub : faites un fork **par groupe**, activez GitHub Actions si nécessaire et configurez vos propres secrets et autorisations Azure. Les secrets du dépôt d’origine ne sont pas transmis au fork.
- Sur GitLab (alternative admise) : créez un projet de groupe à partir du code de départ et utilisez des **Merge Requests dirigées vers `main` de votre projet**, pas vers le dépôt officiel.
- Aucun accès en écriture au dépôt du formateur n’est nécessaire. Transmettez au formateur l’URL de votre dépôt de groupe.

## Commencer

Lisez les documents dans cet ordre :

- [Présentation du projet](docs/01-presentation-projet.md)
- [Consignes techniques](docs/02-consignes-techniques.md)
- [Jalons et validations](docs/03-jalons-validation.md)
- [Exigences CI/CD](docs/04-pipeline-cicd.md)
- [Fonctionnalités avancées](docs/05-bonus-azure.md)
- [Soutenance et livrables](docs/06-soutenance-livrables.md)
- [Ressources officielles](docs/07-ressources.md)
- [Documentation technique de Quiz App : ports, API et configuration](docs/08-documentation-technique.md)
- [Utilisation responsable de l’IA](docs/09-utilisation-ia.md)

**Important :** les comptes Azure for Students peuvent être limités par les crédits, quotas, régions et autorisations. Vérifiez les possibilités de votre abonnement avant de créer des ressources payantes. Supprimez les ressources inutilisées après sauvegarde des preuves et accord du formateur.

## Règles générales

- Travail en groupe ; déposez le lien de votre dépôt et les preuves demandées au formateur.
- Versionnez les fichiers de configuration, les scripts et les workflows **que vous produisez**.
- Ne commitez jamais de mots de passe, URL PostgreSQL contenant des identifiants, clés API, secrets GitHub/GitLab ou fichiers `.env` réels.
- Une démonstration validée reste acquise même si les ressources cloud sont supprimées ensuite.
