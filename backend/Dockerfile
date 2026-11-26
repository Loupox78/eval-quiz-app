# DÉMO J6 UNIQUEMENT (PR brouillon, jamais fusionnée) :
# image d'exécution volontairement obsolète (Node 14, fin de vie 2023) et sans durcissement,
# pour prouver que la CI bloque une image contenant des vulnérabilités CRITICAL.
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:14-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json server.js ./
USER node
EXPOSE 3007
CMD ["node", "server.js"]
