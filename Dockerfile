# Didacta Community wrapper for Railway. The official image runs the Next.js web app (WEB_PORT) and the NestJS API (4000) in one
# container, applies the database migrations on every start, and leaves the first organisation and administrator to a browser
# wizard behind a setup token. Railway's healthcheck and edge dial the injected PORT, so the web app is moved onto it, and the
# first organisation and administrator are created from variables through the same /setup/init call the wizard makes.
# Literals a deployer should never have to type are baked in here as ENV.
# upstream: va360labs/didacta-io
FROM ghcr.io/va360labs/didacta-community:0.1.0-beta.26@sha256:a150d48ab86bc8f107f5fd9e9ccc964462a3d6fbccf9198ea63f8619e4655e1f

COPY --chmod=0755 boot.sh /railway-boot.sh

# DIDACTA_CORE_VERSION must equal the image tag. DATABASE_URL stays unset on purpose: the stock entrypoint derives the
# row-level-security runtime role (didacta_app) from ADMIN_DATABASE_URL, and a DATABASE_URL would bypass it.
ENV NODE_ENV=production \
    DIDACTA_CORE_VERSION=0.1.0-beta.26 \
    API_PORT=4000 \
    STORAGE_DRIVER=local

VOLUME ["/app/data"]
EXPOSE 8080
ENTRYPOINT ["/railway-boot.sh"]
CMD ["start"]
