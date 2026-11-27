# Étape 1 : installation des dépendances de production (npm n'est utile qu'ici)
FROM node:14-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Étape 2 : image d'exécution minimale
FROM node:24-alpine
WORKDIR /app
ENV NODE_ENV=production
# - apk upgrade : applique les correctifs de sécurité Alpine publiés depuis la création de l'image de base
# - suppression de npm / npx / yarn : inutiles à l'exécution, et leurs dépendances
#   internes (tar, glob, minimatch, cross-spawn...) portaient toutes les CVE Node.js du scan initial
RUN apk upgrade --no-cache \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/bin/corepack /usr/local/lib/node_modules/corepack \
           /opt/yarn* /usr/local/bin/yarn /usr/local/bin/yarnpkg
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json server.js ./
USER node
EXPOSE 3007
CMD ["node", "server.js"]
