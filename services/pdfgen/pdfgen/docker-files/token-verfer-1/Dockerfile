# Сборка из корня репозитория (рядом лежит token-verfer-1/):
#   docker build -f docker-files/token-verfer-1/Dockerfile -t token-verfer-1 .
#
# Агент и конфиг — только из `token-verfer-1/ja-netfilter/` (в т.ч. `ja-netfilter.jar` в репозитории).
#
FROM eclipse-temurin:21-jdk-alpine AS compile

WORKDIR /src
COPY token-verfer-1/Main.java .
RUN javac Main.java

# ---------------------------------------------------------------------------
FROM eclipse-temurin:21-jre-alpine AS runtime

RUN apk add --no-cache inotify-tools

WORKDIR /app

COPY token-verfer-1/ja-netfilter/ /app/ja-netfilter/
RUN test -f /app/ja-netfilter/ja-netfilter.jar || (echo "missing token-verfer-1/ja-netfilter/ja-netfilter.jar" >&2; exit 1)

# /app/keys — только том в рантайме. Шаблон power.conf в образе: entrypoint кладёт его в том и вешает symlink на config-demo.
RUN mkdir -p /app/ja-netfilter/config-demo && \
    if [ -f /app/ja-netfilter/config-demo/power.conf ]; then \
        cp /app/ja-netfilter/config-demo/power.conf /app/.baked-power.conf; \
    else \
        printf '[Result]\n' > /app/.baked-power.conf; \
    fi && \
    rm -f /app/ja-netfilter/config-demo/power.conf

COPY --from=compile /src/Main.class /app/

COPY docker-files/token-verfer-1/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8082

ENTRYPOINT ["/entrypoint.sh"]
