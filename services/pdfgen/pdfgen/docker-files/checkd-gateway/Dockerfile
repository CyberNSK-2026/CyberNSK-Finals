# syntax=docker/dockerfile:1
# BuildKit: общий кэш Swift PM + clang с print-service; отдельный `.build` (id) на продукт CheckD — без лишних полных пересборок.
# Сборка: docker compose build — BuildKit по умолчанию; при желании: docker buildx build …
# Сборка из корня репозитория (рядом CheckD/, CheckD-Frontend/, docker-files/):
#   docker build -f docker-files/checkd-gateway/Dockerfile -t checkd-gateway .
#
FROM swift:6.2.4-noble AS builder

WORKDIR /build

COPY CheckD/Package.swift CheckD/Package.resolved ./
RUN --mount=type=cache,id=checkd-swiftpm,target=/root/.cache/org.swift.swiftpm,sharing=locked \
    --mount=type=cache,id=checkd-swift-clang,target=/root/.cache/clang,sharing=locked \
    --mount=type=cache,id=checkd-swift-dotbuild-checkd,target=/build/.build,sharing=locked \
    swift package resolve

COPY CheckD/Sources ./Sources

RUN --mount=type=cache,id=checkd-swiftpm,target=/root/.cache/org.swift.swiftpm,sharing=locked \
    --mount=type=cache,id=checkd-swift-clang,target=/root/.cache/clang,sharing=locked \
    --mount=type=cache,id=checkd-swift-dotbuild-checkd,target=/build/.build,sharing=locked \
    mkdir -p /out && \
    swift build -c release --product CheckD && \
    cp .build/release/CheckD /out/CheckD

# ---------------------------------------------------------------------------
FROM ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        nginx \
        tini \
        coreutils \
        libatomic1 \
        libbsd0 \
        libcurl4t64 \
        libedit2 \
        libgcc-s1 \
        libicu74 \
        libsqlite3-0 \
        libstdc++6 \
        libxml2 \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/lib/swift/linux

COPY --from=builder /out/CheckD /usr/local/bin/CheckD
COPY --from=builder /usr/lib/swift/linux /usr/lib/swift/linux

RUN find /usr/lib/swift/linux/* -maxdepth 1 ! -name '*.so' -delete 2>/dev/null || true; \
    echo '/usr/lib/swift/linux' > /etc/ld.so.conf.d/swift.conf && ldconfig

RUN rm -f /etc/nginx/conf.d/default.conf

COPY docker-files/checkd-gateway/nginx.conf /etc/nginx/nginx.conf
COPY docker-files/checkd-gateway/checkd-gateway.conf /etc/nginx/conf.d/checkd-gateway.conf

COPY CheckD-Frontend/ /var/www/html/

COPY docker-files/checkd-gateway/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/CheckD && \
    mkdir -p /run/nginx /var/lib/nginx /var/log/nginx /etc/nginx/snippets \
        /var/lib/checkd/token-verfer-keys && \
    # Как в entrypoint (resolver + $backend), чтобы nginx -t в образе проходил без DNS checkd-print.
    printf '%s\n' \
        'location /pdf-files/ {' \
        '    resolver 127.0.0.11 ipv6=off valid=10s;' \
        '    set $checkd_print_backend "127.0.0.1:8080";' \
        '    rewrite ^/pdf-files/(.*)$ /files/$1 break;' \
        '    proxy_pass http://$checkd_print_backend;' \
        '    proxy_http_version 1.1;' \
        '}' > /etc/nginx/snippets/pdf-proxy.conf && \
    rm -rf /etc/nginx/sites-enabled/* /etc/nginx/sites-available/default 2>/dev/null || true

EXPOSE 8081 8084 5005

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
