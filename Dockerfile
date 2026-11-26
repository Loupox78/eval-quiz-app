# Étape 1 : build du frontend avec Vite
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# Étape 2 : Nginx sert les fichiers statiques et fait proxy vers le backend
FROM nginx:alpine
# Correctifs de sécurité des paquets système
RUN apk upgrade --no-cache
COPY nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
