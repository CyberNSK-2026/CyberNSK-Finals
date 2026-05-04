# IdentityHub — WebFinger identity service (C / libmicrohttpd)

Сервис поставляется бинарными файлами.

## Описание сервиса

IdentityHub — веб-сервис управления цифровыми идентификаторами по протоколу WebFinger (RFC 7033).
Пользователи регистрируют identity в формате `acct:username@domain`, прикрепляют к ним
свойства (properties, пары ключ-значение), ссылки (links) и псевдонимы (aliases).
При создании identity автоматически генерируется RSA-2048 ключевая пара — приватный ключ
позволяет подписывать свойства (RSA-SHA256 над строкой `key=value`), а публичный ключ
доступен для проверки подписей.

### Стек

| Компонент | Технология |
|-----------|-----------|
| Язык | C11 |
| HTTP сервер | libmicrohttpd |
| JSON | jansson |
| Криптография | OpenSSL (RSA-2048, SHA-256) |
| Сборка | CMake |
| Контейнер | Ubuntu 20.04, порт 8080 |

### Хранение данных

Каждая identity хранится в отдельном бинарном файле `/data/identities/identity_<id>.dat`.
Формат файла:
```
[4B]   id (uint32)
[128B] subject
[32B]  password_hash (SHA-256, без соли)
[4B]   is_public (int)
[8B]   created_at (time_t)
[8B]   updated_at (time_t)
[4B]   alias_count
[N×128B] aliases
[4B]   private_key_len + [N]B PEM
[4B]   public_key_len  + [N]B PEM
[4B]   property_count
  Per property: [64B] key, [256B] value, [4B] is_signed, [4B] sig_len, [sig_len]B signature
[4B]   link_count
  Per link: [64B] rel, [512B] href, [32B] type
```

### API эндпоинты

| Метод | Путь | Аутентификация | Описание |
|-------|------|---------------|----------|
| POST | `/api/create_identity` | нет | Создать identity (subject, password, is_public) |
| POST | `/api/add_property` | пароль | Добавить свойство (key, value), опционально подписать |
| POST | `/api/add_link` | пароль | Добавить ссылку (rel, href, type) |
| POST | `/api/add_alias` | пароль | Добавить псевдоним |
| POST | `/api/sign_property` | пароль | Подписать существующее свойство RSA-SHA256 |
| POST | `/api/verify_property` | нет | Проверить подпись свойства |
| GET | `/api/public_key?subject=` | нет | Получить публичный ключ identity |
| GET | `/api/search?query=` | нет | Поиск identity по подстроке subject |
| GET | `/api/export?id=` | нет | Экспорт identity в бинарном формате |
| GET | `/.well-known/webfinger?resource=&rel=` | нет | WebFinger JRD ответ (RFC 7033) |

### WebFinger ответ (JSON Resource Descriptor)

```json
{
  "subject": "acct:user@domain",
  "aliases": ["https://example.com/users/user"],
  "properties": {
    "http://schema.org/name": "User Name",
    "flag": "FLAG_VALUE"
  },
  "links": [
    {"rel": "http://webfinger.net/rel/profile-page", "href": "https://...", "type": "text/html"}
  ]
}
```

---

## Уязвимости

### VULN-1 — IDOR в /api/search (handlers.c:search_cb)
`GET /api/search?query=<substring>` ищет по подстроке subject среди ВСЕХ identities.
Фильтр `is_public` не применяется — возвращаются properties (включая `flag`) приватных identities.

**Эксплойт:** `GET /api/search?query=acct:` → все identity с флагами.

**Фикс:** добавить `if (!id->is_public) return 0;` в `search_cb`.

---

### VULN-2 — Auth bypass через пустой пароль (handlers.c:check_password)
Проверка пароля делается через:
```c
strncmp(stored_hex, provided_hex, strlen(password))
```
Если `password=""`, то `strlen(password)=0`, `strncmp` сравнивает 0 байт → всегда возвращает 0.
Атакующий может вызывать `add_property`, `sign_property` и т.д. с `"password": ""`.

**Эксплойт:**
```
POST /api/add_property {"subject":"acct:victim@domain", "password":"", "key":"x", "value":"y"}
```
Затем прочитать через WebFinger или search.

**Фикс:** заменить `strlen(password)` на `64` (длина hex SHA256), или использовать `memcmp`.

---

### VULN-3 — WebFinger rel-filter обходит is_public (handlers.c:handle_webfinger)
Без `rel` параметра WebFinger проверяет `is_public` и отдаёт 404.
С `rel` параметром проверка `is_public` пропущена — ответ содержит полный JRD с properties.

**Эксплойт:**
```
GET /.well-known/webfinger?resource=acct:victim@domain&rel=whatever
```

**Фикс:** вынести проверку `is_public` перед ветвлением по `rel`.

---

### VULN-4 — Alias shadowing в /api/public_key (handlers.c:handle_public_key)
`POST /api/add_alias` не проверяет, что alias не совпадает с subject чужой identity.
`GET /api/public_key?subject=X` для прямого subject-поиска проверяет `is_public`.
Но если найден alias-match, проверка `is_public` пропускается (условие `!by_alias` ложно).
Endpoint возвращает properties жертвы (включая `flag`).

**Эксплойт:**
1. Создать свою identity с `alias = "acct:victim@domain"`
2. `GET /api/public_key?subject=acct:victim@domain` → `by_alias` != NULL → is_public не проверяется → properties жертвы (включая flag)

**Фикс:** в `handle_add_alias` проверять `storage_find_by_subject(alias) == NULL`,
и в `handle_public_key` всегда проверять `target->is_public`.

---

### VULN-5 — verify_property утекает значение без аутентификации (handlers.c:handle_verify_property)
`POST /api/verify_property` принимает `subject` и `key`, не требует пароля, не проверяет `is_public`.
Ответ содержит поле `"value"` с полным значением свойства.
Атакующему достаточно знать subject жертвы и ключ `flag`.

**Эксплойт:**
```
POST /api/verify_property {"subject":"acct:victim@domain","key":"flag"}
→ {"valid":false,"key":"flag","value":"FLAG{...}"}
```
Даже если подпись невалидна (valid=false), значение всё равно возвращается.

**Фикс:** не возвращать `value` в ответе, или добавить проверку `is_public` / аутентификацию.

---

### VULN-6 — Бинарный экспорт без авторизации (handlers.c:handle_export)
`GET /api/export?id=<N>` отдаёт сырой бинарный файл identity без аутентификации и без
проверки `is_public`. ID последовательные (1, 2, 3...), легко перебираются.
Бинарный формат фиксированный и документированный — атакующий парсит файл и извлекает
property `flag` из массива properties.

**Эксплойт:**
```python
for i in range(1, 1000):
    r = requests.get(f"http://target:8080/api/export?id={i}")
    if r.status_code == 200:
        # parse binary: skip to properties section, extract flag
        data = r.content
        # ... parse fixed-size fields ...
```

**Фикс:** убрать endpoint, или добавить аутентификацию + проверку `is_public`.
