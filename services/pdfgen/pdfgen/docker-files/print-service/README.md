# CheckD print service (headless Chrome) — Docker

## Сборка образа

Из **корня репозитория** (где лежат `CheckD/` и `docker-files/`):

```bash
docker build -f docker-files/print-service/Dockerfile -t checkd-print-service .
```

Архивы Chrome for Testing в образе — вариант **`linux64`** (x86_64). На Apple Silicon в `docker-compose.yml` для сервиса задано **`platform: linux/amd64`**, иначе бинарь Chrome не запустится.

## Chrome и chromedriver

В образ ставится **Chrome for Testing** и **chromedriver** одной версии (по умолчанию `146.0.7680.80`), с официального bucket Google. Менять версию:

```bash
docker build -f docker-files/print-service/Dockerfile \
  --build-arg CHROME_FOR_TESTING_VERSION=146.0.7680.80 \
  -t checkd-print-service .
```

## Обязательные переменные окружения

- `FILESTORE_PATH` — каталог для временных PDF (создаётся при старте).
- `CHROMEDRIVER_PATH` — исполняемый chromedriver (в образе по умолчанию `/usr/local/bin/chromedriver`).

`entrypoint.sh` проверяет, что обе заданы и что `CHROMEDRIVER_PATH` исполняемый, затем `exec` бинаря сервиса.

Дополнительно в образе заданы `CHROME_PATH` и симлинк `google-chrome` на бинарь CfT. Для headless в Docker без X11: **`CHROME_DOCKER_SAFE=1`** (в Dockerfile уже выставлено); при необходимости можно отключить, задав `0`.

## Публичный URL в ответе `pdfurl`

Приложение собирает ссылку вида `http://<хост>:<порт>/files/<имя>.pdf`:

- **`PRINT_PUBLIC_HOSTNAME`** — хост в этом URL (по умолчанию `print-service`, если переменная не задана или пустая). В compose обычно ставят **имя сервиса** (например `checkd-print`), чтобы другие контейнеры в той же сети открывали nginx.
- **`PRINT_PUBLIC_PORT`** — порт nginx для `/files/` (по умолчанию `8080`).

## Ограничение «только своя docker-сеть, без интернета»

В `docker-compose.yml` сеть `print_internal` объявлена с **`internal: true`**: исходящий трафик в интернет из контейнеров в этой сети недоступен, связь с **другими сервисами в той же сети** — доступна.

Чтобы другой сервис (например API) был доступен принтеру, подключите тот же сервис к сети `print_internal` (или используйте общий compose-файл с одной internal-сетью).

Порты `8080`/`5004` проброшены на хост только для отладки; в проде их можно убрать и ходить только из других контейнеров по DNS-сервиса.

## Лимит памяти, `/dev/shm` и перезапуск

У сервиса `checkd-print` задан **`shm_size: 1gb`** (мало `/dev/shm` по умолчанию → Chrome часто падает с `session not created: Chrome instance exited`) и лимит памяти **1 GiB** (`deploy.resources.limits.memory`) под Swift + nginx + chromedriver + headless Chrome. Нужен актуальный Docker Compose (v2), который применяет `deploy` к обычному `docker compose up`.

Политика **`restart: unless-stopped`**: при **OOM** (или любом аварийном выходе процесса PID 1) контейнер завершится, и Docker Compose **снова запустит** сервис. Явный `docker compose stop` / `down` перезапуск не включает.

## Логи (`docker logs`)

В контейнере stdout не TTY: **`print` в Swift часто не использует тот же libc `FILE*`, что настраивает `setvbuf`**, а **`stdbuf`** через `LD_PRELOAD` не всегда влияет на Swift-бинарник — в итоге `docker compose up` / `docker logs` могли быть пустыми.

Сервис пишет диагностические строки через **`write(2, …)`** (stderr), минуя stdio, плюс в `entrypoint.sh` остаётся **`stdbuf -oL -eL`** на случай дочерних процессов. Логи chromedriver/Chrome идут в поток контейнера, а не в `/dev/null`.
