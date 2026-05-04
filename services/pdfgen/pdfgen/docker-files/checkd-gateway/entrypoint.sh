#!/bin/sh
set -eu
# /pdf-files/ → CheckD Print service. resolver + переменная: резолв при запросе (Docker DNS 127.0.0.11),
# иначе nginx падает при старте, если checkd-print ещё не в DNS.
mkdir -p /etc/nginx/snippets /run/nginx /var/lib/nginx /var/log/nginx

PH="${CHECKD_PRINT_SERVICE_HOST:-checkd-print}"
PP="${CHECKD_PRINT_SERVICE_PORT:-8080}"

# С переменной в proxy_pass nginx не делает подмену префикса location → URI как со статическим upstream;
# без rewrite на print уходит GET /files/ и 403 (autoindex off на каталоге).
{
    printf '%s\n' 'location /pdf-files/ {'
    printf '%s\n' '    resolver 127.0.0.11 ipv6=off valid=10s;'
    printf '    set $checkd_print_backend "%s:%s";\n' "$PH" "$PP"
    printf '%s\n' '    rewrite ^/pdf-files/(.*)$ /files/$1 break;'
    printf '%s\n' '    proxy_pass http://$checkd_print_backend;'
    printf '%s\n' '    proxy_http_version 1.1;'
    printf '%s\n' '}'
} > /etc/nginx/snippets/pdf-proxy.conf

nginx

exec stdbuf -oL -eL /usr/local/bin/CheckD
