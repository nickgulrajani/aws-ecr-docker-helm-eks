# --- Builder ---
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY src ./src

# --- Runtime ---
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=8080
# run as non-root
RUN addgroup -S app && adduser -S -G app app
COPY --from=build /app /app
USER app
EXPOSE 8080
# container healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
CMD ["node", "src/server.js"]
