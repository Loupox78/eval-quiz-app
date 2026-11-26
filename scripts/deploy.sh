#!/usr/bin/env bash
# Déploiement de Quiz App sur Azure avec Azure CLI.
#
# Usage :
#   ./scripts/deploy.sh infra    # J3 : groupe de ressources + Azure Container Registry
#   ./scripts/deploy.sh images   # J3 : build linux/amd64 + push des images dans l'ACR
#   ./scripts/deploy.sh apps     # J4 : environnement + Container Apps backend et frontend
#   ./scripts/deploy.sh all      # les trois étapes à la suite
#   ./scripts/deploy.sh status   # affiche l'état des ressources
#
# Prérequis : az login effectué, Docker démarré, lancé depuis la racine du dépôt.
# Secrets (étape apps) : lus depuis les variables d'environnement ou le fichier .env.azure
# (jamais versionné, voir .env.azure.example). Aucun secret n'est écrit dans ce script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck source=scripts/config.sh
source "$SCRIPT_DIR/config.sh"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mErreur : %s\033[0m\n' "$*" >&2; exit 1; }

check_prereqs() {
  command -v az >/dev/null || die "Azure CLI (az) introuvable"
  az account show -o none 2>/dev/null || die "non connecté : lancez 'az login'"
  log "Abonnement : $(az account show --query name -o tsv) | Région ACR : $LOCATION | Région apps : $ACA_LOCATION | Tag : $TAG"
}

acr_server() { az acr show -n "$ACR_NAME" --query loginServer -o tsv; }

# ---------------------------------------------------------------------------
# J3 — Groupe de ressources + ACR
# ---------------------------------------------------------------------------
deploy_infra() {
  log "Enregistrement des fournisseurs de ressources (sans effet s'ils le sont déjà)"
  for ns in Microsoft.ContainerRegistry Microsoft.App Microsoft.OperationalInsights; do
    az provider register -n "$ns" -o none
  done

  log "Groupe de ressources $RG"
  az group create -n "$RG" -l "$LOCATION" -o none

  if az acr show -n "$ACR_NAME" -o none 2>/dev/null; then
    log "ACR $ACR_NAME déjà présent"
  else
    log "Création de l'ACR $ACR_NAME (SKU Basic, compte admin désactivé)"
    az acr create -g "$RG" -n "$ACR_NAME" -l "$LOCATION" --sku Basic --admin-enabled false -o none
  fi
  log "ACR prêt : $(acr_server)"
}

# ---------------------------------------------------------------------------
# J3 — Build et publication des images
# ---------------------------------------------------------------------------
push_images() {
  command -v docker >/dev/null || die "Docker introuvable"
  docker info >/dev/null 2>&1 || die "Docker n'est pas démarré"
  local server; server="$(acr_server)"

  log "Connexion de Docker à l'ACR (jeton temporaire Azure AD)"
  az acr login -n "$ACR_NAME"

  log "Build + push backend : $server/$BACKEND_IMAGE:$TAG ($PLATFORM)"
  docker buildx build --platform "$PLATFORM" \
    -t "$server/$BACKEND_IMAGE:$TAG" -t "$server/$BACKEND_IMAGE:latest" \
    --push ./backend

  log "Build + push frontend : $server/$FRONTEND_IMAGE:$TAG ($PLATFORM)"
  docker buildx build --platform "$PLATFORM" \
    -t "$server/$FRONTEND_IMAGE:$TAG" -t "$server/$FRONTEND_IMAGE:latest" \
    --push .

  log "Images présentes dans l'ACR"
  az acr repository show-tags -n "$ACR_NAME" --repository "$BACKEND_IMAGE" -o table
  az acr repository show-tags -n "$ACR_NAME" --repository "$FRONTEND_IMAGE" -o table
}

# ---------------------------------------------------------------------------
# J4 — Environnement + Container Apps
# ---------------------------------------------------------------------------
load_secrets() {
  if [[ -f .env.azure ]]; then
    set -a; # exporte toutes les variables lues
    # shellcheck disable=SC1091
    source .env.azure
    set +a
  fi
  local missing=()
  for v in DATABASE_URL RESEND_API_KEY ADMIN_PASSWORD JWT_SECRET; do
    [[ -n "${!v:-}" ]] || missing+=("$v")
  done
  ((${#missing[@]} == 0)) || die "variables manquantes : ${missing[*]} (voir .env.azure.example)"
  ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
  FROM_EMAIL="${FROM_EMAIL:-Quiz App <noreply@notifications.labformation.fr>}"
}

app_exists() { az containerapp show -n "$1" -g "$RG" -o none 2>/dev/null; }

deploy_apps() {
  load_secrets
  local server; server="$(acr_server)"
  az extension add -n containerapp --upgrade -y -o none 2>/dev/null || true

  # Mode WorkloadProfiles (standard) imposé explicitement : sans cette option, Azure crée
  # désormais un environnement "Express", qui interdit l'appel interne http://quiz-backend,
  # le HTTP interne (allowInsecure) et l'identité managée système.
  if az containerapp env show -n "$ACA_ENV" -g "$RG" -o none 2>/dev/null; then
    local mode
    mode="$(az containerapp env show -n "$ACA_ENV" -g "$RG" --query properties.environmentMode -o tsv)"
    [[ "$mode" != "Express" ]] || die "l'environnement $ACA_ENV est en mode Express. Supprimez-le :
  az containerapp env delete -n $ACA_ENV -g $RG --yes
puis relancez ./scripts/deploy.sh apps"
    log "Environnement $ACA_ENV déjà présent (mode ${mode:-standard})"
  else
    log "Création de l'environnement Container Apps $ACA_ENV dans $ACA_LOCATION (mode WorkloadProfiles, plusieurs minutes)"
    az containerapp env create -n "$ACA_ENV" -g "$RG" -l "$ACA_LOCATION" \
      --environment-mode WorkloadProfiles --logs-destination log-analytics -o none
  fi

  # Secrets stockés dans la Container App, injectés en variables via secretref:
  local secrets=(
    "database-url=$DATABASE_URL"
    "resend-api-key=$RESEND_API_KEY"
    "admin-password=$ADMIN_PASSWORD"
    "jwt-secret=$JWT_SECRET"
  )
  local backend_env=(
    "DATABASE_URL=secretref:database-url"
    "RESEND_API_KEY=secretref:resend-api-key"
    "ADMIN_PASSWORD=secretref:admin-password"
    "JWT_SECRET=secretref:jwt-secret"
    "ADMIN_USERNAME=$ADMIN_USERNAME"
    "FROM_EMAIL=$FROM_EMAIL"
  )

  if app_exists "$BACKEND_APP"; then
    log "Mise à jour du backend $BACKEND_APP -> $BACKEND_IMAGE:$TAG"
    az containerapp secret set -n "$BACKEND_APP" -g "$RG" --secrets "${secrets[@]}" -o none
    az containerapp update -n "$BACKEND_APP" -g "$RG" \
      --image "$server/$BACKEND_IMAGE:$TAG" --set-env-vars "${backend_env[@]}" -o none
  else
    log "Création du backend $BACKEND_APP (ingress interne, port 3007)"
    # --registry-identity system : identité managée + rôle AcrPull, pas de mot de passe registre
    # --ingress internal         : joignable uniquement depuis l'environnement (pas d'Internet)
    # --allow-insecure           : autorise HTTP en interne (le frontend appelle http://quiz-backend)
    az containerapp create -n "$BACKEND_APP" -g "$RG" --environment "$ACA_ENV" \
      --image "$server/$BACKEND_IMAGE:$TAG" \
      --registry-server "$server" --registry-identity system \
      --ingress internal --target-port 3007 --transport http --allow-insecure \
      --cpu 0.25 --memory 0.5Gi --min-replicas 0 --max-replicas 1 \
      --secrets "${secrets[@]}" --env-vars "${backend_env[@]}" -o none
  fi

  if app_exists "$FRONTEND_APP"; then
    log "Mise à jour du frontend $FRONTEND_APP -> $FRONTEND_IMAGE:$TAG"
    az containerapp update -n "$FRONTEND_APP" -g "$RG" \
      --image "$server/$FRONTEND_IMAGE:$TAG" --set-env-vars "BACKEND_HOST=$BACKEND_APP" -o none
  else
    log "Création du frontend $FRONTEND_APP (ingress externe, port 8080)"
    az containerapp create -n "$FRONTEND_APP" -g "$RG" --environment "$ACA_ENV" \
      --image "$server/$FRONTEND_IMAGE:$TAG" \
      --registry-server "$server" --registry-identity system \
      --ingress external --target-port 8080 \
      --cpu 0.25 --memory 0.5Gi --min-replicas 0 --max-replicas 1 \
      --env-vars "BACKEND_HOST=$BACKEND_APP" -o none
  fi

  show_status
}

show_status() {
  log "Container Apps"
  az containerapp list -g "$RG" \
    --query "[].{App:name, Etat:properties.runningStatus, Image:properties.template.containers[0].image, URL:properties.configuration.ingress.fqdn}" \
    -o table || true
  local fqdn
  fqdn="$(az containerapp show -n "$FRONTEND_APP" -g "$RG" --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || true)"
  [[ -n "$fqdn" ]] && log "Application : https://$fqdn   (santé : https://$fqdn/health)"
  return 0
}

main() {
  local step="${1:-}"
  case "$step" in
    infra)  check_prereqs; deploy_infra ;;
    images) check_prereqs; push_images ;;
    apps)   check_prereqs; deploy_apps ;;
    all)    check_prereqs; deploy_infra; push_images; deploy_apps ;;
    status) check_prereqs; show_status ;;
    *) sed -n '2,12p' "$0"; exit 1 ;;
  esac
}

main "$@"
