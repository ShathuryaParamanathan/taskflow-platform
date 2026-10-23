# Stage 1: Install production dependencies
FROM node:24-alpine AS dependencies
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Stage 2: Run the application
FROM node:24-alpine AS production
ENV NODE_ENV=production
ENV PORT=3000
WORKDIR /app
COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package*.json ./
COPY --chown=node:node src ./src
COPY --chown=node:node migrations ./migrations
COPY --chown=node:node openapi.yaml ./openapi.yaml
USER node
EXPOSE 3000
CMD ["node", "src/server.js"]
