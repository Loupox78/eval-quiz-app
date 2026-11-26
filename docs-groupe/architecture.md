# Architecture de Quiz App (local, cloud et chaîne de livraison)

Schémas faits par le groupe (Mermaid, affichés directement par GitHub).

## 1. En local (Docker Compose)

```mermaid
flowchart LR
  N["Navigateur"] -- "http://localhost:8087" --> F
  subgraph C["Réseau Docker Compose"]
    F["frontend<br/>Nginx non-root :8080"] -- "/api, /health<br/>http://backend:3007" --> B["backend<br/>Node 24 / Express :3007"]
    B -- "postgres://db:5432" --> D[("db<br/>PostgreSQL 16")]
  end
  D --- V[["volume pgdata"]]
  I["database/init.sql"] -. "1er démarrage du volume" .-> D
```

- Un seul port ouvert sur la machine : **8087** (→ 8080 dans le conteneur frontend).
- `backend` et `db` ne sont joignables que dans le réseau Compose (par leur nom de service).
- Les données sont dans le **volume `pgdata`** : `docker compose down` puis `up` les garde, seul `down -v` les efface.

## 2. Sur Azure

```mermaid
flowchart LR
  N["Navigateur"] -- "HTTPS" --> F
  subgraph RG["Groupe rg-quiz-app (switzerlandnorth)"]
    ACR[("ACR acrquizloupox78<br/>images taguées par commit")]
    ID["Identité managée<br/>id-quiz-acrpull (AcrPull)"]
    subgraph ENV["Environnement Container Apps cae-quiz-app"]
      F["quiz-frontend<br/>ingress externe :8080"] -- "http://quiz-backend<br/>(interne)" --> B["quiz-backend<br/>ingress interne :3007<br/>secrets : database-url, jwt-secret..."]
    end
    ID -. "tire les images" .-> ACR
    F -. image .-> ACR
    B -. image .-> ACR
  end
  B -- "TLS verify-full" --> NEON[("Neon PostgreSQL<br/>AWS Frankfurt")]
```

- Seul le **frontend** a une URL publique. Le backend est en ingress interne.
- Les apps tirent leurs images de l'ACR avec une **identité managée** (rôle `AcrPull`), sans mot de passe de registre.
- La base n'est plus un conteneur : c'est **Neon** (PostgreSQL managé), connexion chiffrée. La chaîne de connexion est un **secret** Container Apps.

## 3. Chaîne de livraison (GitHub Actions)

```mermaid
flowchart LR
  DEV["Branche feature/*<br/>(ex. modif d'une question)"] --> PR["Pull Request<br/>vers main du fork"]
  subgraph CI["CI — ci.yml (sur la PR)"]
    BUILD["Build des 2 images"] --> TRIVY{"Trivy :<br/>CRITICAL ?"}
    TRIVY -- "oui" --> KO["Job rouge<br/>fusion bloquée"]
    TRIVY -- "non" --> OK["Job vert"]
    IT["Test de démarrage<br/>Compose + /health"]
  end
  PR --> BUILD
  PR --> IT
  OK --> REV["Revue + approbation"]
  IT --> REV
  REV --> MERGE["Fusion dans main"]
  subgraph CD["CD — cd.yml (après fusion)"]
    LOGIN["Connexion Azure<br/>OIDC, sans secret"] --> PUSH["Build + Trivy + push<br/>ACR tag = commit"]
    PUSH --> UPD["az containerapp update<br/>backend + frontend"]
    UPD --> CHECK["Nouvelle révision<br/>test /health"]
  end
  MERGE --> LOGIN
```

- Une PR ne déploie **jamais** rien : elle n'a ni secret ni accès Azure.
- Le déploiement ne se lance qu'après fusion dans `main`.
- Le tag d'image = hash du commit → on sait exactement quel code tourne dans chaque révision.

## Tableau des ports

| Composant | Dans le conteneur | Exposé en local | Exposé sur Azure |
|---|---|---|---|
| frontend (Nginx) | 8080 | 8087 | HTTPS 443 (URL publique) |
| backend (Express) | 3007 | non | non (interne uniquement) |
| PostgreSQL | 5432 | non | — (Neon, hors Azure) |
