# Bichon on Railway - https://github.com/aalfath/bichon-railway-template
# Upstream: https://github.com/rustmailer/bichon (AGPL-3.0), official image pinned by version and digest.
ARG BICHON_IMAGE=rustmailer/bichon:2.4.4@sha256:a282e5abf942a7b761afb48b4b3529f3be4a823f6e32d06b65a3578bd119a980

# Build the small statvfs shim against the same glibc as the runtime image.
FROM ${BICHON_IMAGE} AS shim
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*
COPY freefloor.c /src/freefloor.c
RUN gcc -O2 -Wall -Werror -shared -fPIC -o /src/freefloor.so /src/freefloor.c -ldl

FROM ${BICHON_IMAGE}
COPY --from=shim /src/freefloor.so /opt/railway/freefloor.so
COPY start.sh /opt/railway/start.sh
ENV BICHON_ROOT_DIR=/data/bichon \
    BICHON_BIND_IP=:: \
    BICHON_ANSI_LOGS=false
WORKDIR /data
EXPOSE 15630
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -fs --max-time 4 "http://127.0.0.1:${PORT:-15630}/healthz" || exit 1
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/opt/railway/start.sh"]
