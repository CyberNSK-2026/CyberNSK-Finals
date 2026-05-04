#!/bin/sh
set -eu

JAVA_PID_FILE=/tmp/token-verfer-java.pid

prepare() {
    mkdir -p /app/keys /app/ja-netfilter/config-demo
    if [ ! -f /app/keys/power.conf ]; then
        cp /app/.baked-power.conf /app/keys/power.conf
    fi
    rm -f /app/ja-netfilter/config-demo/power.conf
    ln -sf /app/keys/power.conf /app/ja-netfilter/config-demo/power.conf
}

stop_java() {
    if [ ! -f "$JAVA_PID_FILE" ]; then
        return 0
    fi
    pid=$(cat "$JAVA_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        i=0
        while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 150 ]; do
            i=$((i + 1))
            sleep 0.1
        done
        kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f "$JAVA_PID_FILE"
}

start_java_bg() {
    (
        cd /app
        exec java \
            --add-opens=java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED \
            --add-opens=java.base/jdk.internal.org.objectweb.asm.tree=ALL-UNNAMED \
            -javaagent:/app/ja-netfilter/ja-netfilter.jar=demo \
            -cp /app \
            Main
    ) &
    echo $! >"$JAVA_PID_FILE"
}

trap 'stop_java; exit 0' TERM INT

prepare
start_java_bg

# Следим за томом: при изменении power.conf на диске — перезапуск JVM (ja-netfilter подхватит конфиг).
inotifywait -m \
    -e close_write,modify,moved_to,move_self,delete_self,attrib \
    --format '%f' \
    /app/keys 2>/dev/null | while IFS= read -r fname; do
    [ "$fname" = "power.conf" ] || continue
    echo "token-verfer: power.conf changed, restarting Java..." >&2
    stop_java
    prepare
    start_java_bg
done
