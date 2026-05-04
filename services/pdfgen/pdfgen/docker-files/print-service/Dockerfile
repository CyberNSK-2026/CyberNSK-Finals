# syntax=docker/dockerfile:1
# BuildKit: общий Swift PM + clang с gateway; свой кэш `.build` для CheckDPrintService; apt, Chrome zip.
# Из корня репозитория (рядом лежат каталоги CheckD и docker-files):
#   docker build -f docker-files/print-service/Dockerfile -t checkd-print-service .
#
# Chrome for Testing и chromedriver — одна и та же версия (см. ARG ниже).
#
FROM swift:6.2.4-noble AS builder

WORKDIR /build

COPY CheckD/Package.swift CheckD/Package.resolved ./
RUN --mount=type=cache,id=checkd-swiftpm,target=/root/.cache/org.swift.swiftpm,sharing=locked \
    --mount=type=cache,id=checkd-swift-clang,target=/root/.cache/clang,sharing=locked \
    --mount=type=cache,id=checkd-swift-dotbuild-print,target=/build/.build,sharing=locked \
    swift package resolve

COPY CheckD/Sources ./Sources

RUN --mount=type=cache,id=checkd-swiftpm,target=/root/.cache/org.swift.swiftpm,sharing=locked \
    --mount=type=cache,id=checkd-swift-clang,target=/root/.cache/clang,sharing=locked \
    --mount=type=cache,id=checkd-swift-dotbuild-print,target=/build/.build,sharing=locked \
    mkdir -p /out && \
    swift build -c release --product CheckDPrintService && \
    cp .build/release/CheckDPrintService /out/CheckDPrintService

# ---------------------------------------------------------------------------
FROM ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive

ARG CHROME_FOR_TESTING_VERSION=146.0.7680.80
ENV CHROME_FOR_TESTING_VERSION=${CHROME_FOR_TESTING_VERSION}

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
        tini \
        coreutils \
        nginx \
        apache2-utils \
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
        fonts-liberation \
        libasound2t64 \
        libatk-bridge2.0-0 \
        libatk1.0-0 \
        libcairo2 \
        libcups2 \
        libdbus-1-3 \
        libdrm2 \
        libexpat1 \
        libfontconfig1 \
        libgbm1 \
        libglib2.0-0t64 \
        libgtk-3-0t64 \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libpangocairo-1.0-0 \
        libx11-6 \
        libx11-xcb1 \
        libxcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxi6 \
        libxkbcommon0 \
        libxrandr2 \
        libxrender1 \
        libxshmfence1 \
        libxss1 \
        libxtst6 \
        xdg-utils \
        && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/var/cache/chrome-cft,sharing=locked \
    set -eux; \
    V="${CHROME_FOR_TESTING_VERSION}"; \
    C="/var/cache/chrome-cft/chrome-linux64-${V}.zip"; \
    D="/var/cache/chrome-cft/chromedriver-linux64-${V}.zip"; \
    test -s "$C" || curl -fsSL -o "$C" "https://storage.googleapis.com/chrome-for-testing-public/${V}/linux64/chrome-linux64.zip"; \
    test -s "$D" || curl -fsSL -o "$D" "https://storage.googleapis.com/chrome-for-testing-public/${V}/linux64/chromedriver-linux64.zip"; \
    unzip -q "$C" -d /opt/chrome-for-testing; \
    unzip -q "$D" -d /tmp/cft; \
    install -m0755 /tmp/cft/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver; \
    rm -rf /tmp/cft; \
    ln -sf "/opt/chrome-for-testing/chrome-linux64/chrome" /usr/local/bin/google-chrome

ENV CHROMEDRIVER_PATH=/usr/local/bin/chromedriver
ENV CHROME_PATH=/opt/chrome-for-testing/chrome-linux64/chrome
ENV CHROME_DOCKER_SAFE=1

RUN mkdir -p /usr/lib/swift/linux

COPY --from=builder /out/CheckDPrintService /usr/local/bin/CheckDPrintService
COPY --from=builder /usr/lib/swift/linux /usr/lib/swift/linux

RUN find /usr/lib/swift/linux/* -maxdepth 1 ! -name '*.so' -delete 2>/dev/null || true; \
    echo '/usr/lib/swift/linux' > /etc/ld.so.conf.d/swift.conf && ldconfig

COPY docker-files/print-service/nginx.conf /etc/nginx/nginx.conf
COPY docker-files/print-service/default.conf /etc/nginx/sites-available/default

COPY docker-files/print-service/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/CheckDPrintService && \
    mkdir -p /run/nginx /var/lib/nginx /var/log/nginx /var/www/html && \
    mkdir -p /etc/nginx/sites-enabled && \
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default && \
    printf '%s\n' 'stub' > /var/www/html/index.html

EXPOSE 8080 5004

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
