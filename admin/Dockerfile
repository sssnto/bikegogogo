FROM node:22-bookworm-slim AS deps

WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM deps AS build
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:22-bookworm-slim AS runner

ARG APP_REVISION=development
ENV NODE_ENV=production
ENV PORT=8082
ENV APP_REVISION=$APP_REVISION

WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
COPY public ./public

EXPOSE 8082
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:' + (process.env.PORT || 8082) + '/health').then((r) => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

USER node
CMD ["node", "--enable-source-maps", "dist/index.js"]
