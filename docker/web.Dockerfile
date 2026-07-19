# Build from the repo root:
#   docker build -f docker/web.Dockerfile -t coortweet-web .
# Walkthrough JSON must exist (Rscript api/scripts/build_walkthrough.R) —
# it is committed under web/public/walkthrough.
FROM node:22-alpine AS build
WORKDIR /app
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web .
RUN npm run build

FROM caddy:2-alpine
COPY docker/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /app/dist /srv
EXPOSE 80
