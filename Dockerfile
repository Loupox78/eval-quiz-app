# Étape 1 : build du frontend avec Vite
FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# Étape 2 : Nginx non-root, variante "slim" (sans modules xslt / image-filter / njs ni curl)
FROM nginxinc/nginx-unprivileged:alpine-slim
# apk upgrade doit être lancé en root, puis on revient à l'utilisateur non privilégié "nginx"
USER root
RUN apk upgrade --no-cache
USER nginx
# Modèle de configuration : l'adresse du backend est injectée au démarrage via BACKEND_HOST
COPY --chown=nginx:nginx nginx/templates/default.conf.template /etc/nginx/templates/default.conf.template
ENV BACKEND_HOST=backend:3007
COPY --from=build --chown=nginx:nginx /app/dist /usr/share/nginx/html
# Un utilisateur non-root ne peut pas écouter sur un port < 1024 : Nginx écoute sur 8080
EXPOSE 8080
