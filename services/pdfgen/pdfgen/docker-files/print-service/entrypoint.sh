#!/bin/sh
set -eu

if [ -z "${FILESTORE_PATH:-}" ]; then
    echo "error: FILESTORE_PATH is required" >&2
    exit 1
fi

if [ -z "${CHROMEDRIVER_PATH:-}" ]; then
    echo "error: CHROMEDRIVER_PATH is required" >&2
    exit 1
fi

if [ ! -x "$CHROMEDRIVER_PATH" ]; then
    echo "error: CHROMEDRIVER_PATH is not an executable file: $CHROMEDRIVER_PATH" >&2
    exit 1
fi

mkdir -p "$FILESTORE_PATH"

# Без лишнего слэша перед тем как подставить в alias.
FILESTORE_PATH="${FILESTORE_PATH%/}"

# Путь к файлам PDF для location /files/ (nginx не читает ENV в конфиге).
{
    printf '%s\n' 'location /files/ {'
    printf '    alias %s/;\n' "$FILESTORE_PATH"
    printf '%s\n' '    autoindex off;'
    printf '%s\n' '    default_type application/pdf;'
    printf '%s\n' '}'
} > /etc/nginx/filestore-location.conf

nginx

# В контейнере stdout/stderr не TTY — без line-buffer `print`/`docker logs` почти пустые.
exec stdbuf -oL -eL /usr/local/bin/CheckDPrintService
