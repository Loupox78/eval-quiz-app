# Étape 1 : installation des dépendances (npm n'est utile qu'ici)
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Étape 2 : image d'exécution minimale
FROM node:20-alpine
# Correctifs de sécurité des paquets système (openssl, musl...)
# + suppression de npm/corepack, inutiles pour exécuter l'app et porteurs de CVE
RUN apk upgrade --no-cache \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
           /opt/yarn* /usr/local/bin/yarn /usr/local/bin/yarnpkg
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json server.js ./
USER node
EXPOSE 3007
CMD ["node", "server.js"]
