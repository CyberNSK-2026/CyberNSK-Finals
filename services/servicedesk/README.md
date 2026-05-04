# ServiceDesk

## Бизнес логика

ServiceDesk закрывает простой сценарий внутреннего саппорта:

- customer регистрируется и создает тикет;
- support разбирает обращения, отвечает и назначает обработку;
- по кейсу можно прикладывать артефакты, строить отчет и выгружать export;
- при необходимости кейс шарится внешнему reviewer по share-link;
- события по тикетам можно отправлять во внешние webhook-интеграции.

Это не полноразмерная ITSM-платформа. Здесь нет проектов, SLA, workflow-конструктора,
почтового шлюза, тонкой RBAC-модели и сложной админки.

## Что входит в сервис

### Основные возможности

- регистрация и логин по JWT;
- профиль пользователя и directory;
- создание и обновление тикетов;
- сообщения по тикету;
- загрузка и скачивание артефактов;
- генерация отчетов по Jinja2-шаблону;
- текстовый export кейса;
- публичные share-link для reviewer-доступа;
- webhook-интеграции по событиям тикетов;
- отдельный `dispatchboard` для delivery receipts;
- reverse proxy через `nginx`.

### Сущности

- `User` - пользователь, профиль, роль, workspace, queue scope, контактный телефон.
- `Ticket` - кейс с номером `SD-XXXXXX`, описанием, статусом, приоритетом и
  служебными полями.
- `TicketMessage` - сообщение внутри кейса.
- `Artifact` - вложение, которое хранится на диске и связано с тикетом.
- `Report` - результат рендера шаблона по тикету.
- `Integration` - webhook-подписка на события.
- `ShareToken` - публичная reviewer-ссылка на кейс.
- `TicketEvent` - запись о событии по тикету для ленты уведомлений.

## Архитектура

```text
client -> nginx:8080 -> app:8080 -> postgres
                        |
                        +-> dispatchboard:8081
```

### Компоненты

- `servicedesk/app` - FastAPI-приложение с API, бизнес-логикой и работой с БД.
- `servicedesk/dispatchboard` - отдельный FastAPI-сервис, который хранит receipts
  от delivery webhook'ов.
- `servicedesk/nginx` - внешний reverse-proxy на порт `8080`.
- `postgres` - основная база данных.

### Сети и storage

- `internal` - внутренняя сеть между `app`, `db`, `dispatchboard`.
- `external` - сеть между `nginx` и `app`.
- `pgdata` - volume базы данных.
- `uploads` - volume артефактов, snapshots и exports.

## Роли и модель доступа

### Customer может

- зарегистрироваться и войти;
- смотреть и менять свой профиль;
- создавать свои тикеты;
- смотреть только доступные ему тикеты;
- менять у своих тикетов пользовательские поля;
- писать сообщения и загружать артефакты в доступные ему тикеты;
- генерировать отчеты по своим тикетам;
- делать export и share-link своих тикетов;
- создавать интеграции, привязанные к своим тикетам;
- скачивать артефакты доступных ему тикетов;
- смотреть свою ленту уведомлений.

### Support может

- видеть все тикеты;
- читать и редактировать любые тикеты;
- назначать агента и резолюцию;
- читать данные пользователей по id;
- создавать ticket-scoped и workspace-scoped интеграции;
- получать ленту событий по назначенным ему кейсам.

### Что сервис не умеет

- нет удаления тикетов, сообщений, артефактов, отчетов и пользователей;
- нет password reset, email verification и invite flow;
- нет multi-org / multi-project модели;
- нет UI или API для revoke share-token;
- нет настоящей очереди задач: webhook-delivery идет best-effort через asyncio;
- нет версии схемы БД с отдельным миграционным инструментом;
- нет официальной публичной OpenAPI-документации на `/docs` и `/redoc`.

## Что можно менять в тикете

### Обычный пользователь

Пользовательский апдейт ограничен следующими полями:

- `title`
- `description`
- `report_template`
- `vendor_case_id`
- `device_serial`
- `automation_secret`

### Support

Support дополнительно может менять служебные поля:

- `status`
- `priority`
- `resolution`
- `agent_id`

## API обзор

### Auth

- `POST /api/auth/register` - регистрация по JSON.
- `POST /api/auth/login` - логин через form data.

### Users

- `GET /api/users/me` - текущий профиль.
- `PATCH /api/users/me` - обновление профиля.
- `GET /api/users/{user_id}` - просмотр пользователя по id.
- `GET /api/users` - directory.

### Tickets

- `POST /api/tickets`
- `GET /api/tickets`
- `GET /api/tickets/{ticket_id}`
- `PATCH /api/tickets/{ticket_id}`
- `GET /api/tickets/{ticket_id}/messages`
- `POST /api/tickets/{ticket_id}/messages`
- `GET /api/tickets/{ticket_id}/artifacts`
- `POST /api/tickets/{ticket_id}/artifacts`
- `GET /api/tickets/{ticket_id}/artifacts/{artifact_id}`
- `GET /api/tickets/{ticket_id}/artifacts/{artifact_id}/download`

### Reports

- `POST /api/reports`
- `GET /api/reports/{report_id}`

### Files

- `POST /api/files/exports`
- `GET /api/files/exports/download`
- `GET /api/files/artifact/{artifact_id}`

### Share

- `POST /api/share`
- `GET /api/share/{token}`

### Integrations

- `POST /api/integrations`
- `GET /api/integrations`
- `PATCH /api/integrations/{integration_id}`
- `POST /api/integrations/{integration_id}/trigger`

### Notifications

- `GET /api/notifications`

### Service

- `GET /health`

## Что важно знать про поведение

### Аутентификация

- Access token - JWT с алгоритмом `HS256`.
- `JWT_SECRET` можно задать через `servicedesk/app/.env` или обычные env-переменные.
- Если `JWT_SECRET` не задан, сервис генерирует его сам на старте процесса.
- При смене `JWT_SECRET` ранее выданные токены перестают проходить проверку.

### Support-аккаунт

- На старте сервис создает или обновляет support-аккаунт.
- По умолчанию используются:
  - `SUPPORT_USERNAME=support`
  - `SUPPORT_EMAIL=support@servicedesk.local`
- `SUPPORT_PASSWORD` можно задать через `servicedesk/app/.env` или через
  env-переменные.
- Если `SUPPORT_PASSWORD` не задан и support-аккаунт создается впервые, пароль
  генерируется автоматически и пишется в логи `app`.
- Если support-аккаунт уже существует и `SUPPORT_PASSWORD` не задан, сервис не
  перетирает существующий пароль на каждом старте.

### Хранение файлов

- Артефакты лежат в `/uploads/cases/<case_number>/`.
- Snapshot кейса лежит в `/uploads/cases/<case_number>/snapshot.txt`.
- Exports лежат в `/uploads/exports/`.

### Integrations

- Интеграция может быть ticket-scoped или workspace-scoped.
- Payload формируется приложением автоматически в зависимости от `provider`.
- Поддерживаемые типы:
  - `discord`
  - `slack`
  - `teams`
  - `generic_webhook`
- Для отладки есть ручной trigger через `POST /api/integrations/{id}/trigger`.

### Reports

- По умолчанию отчет рендерится из `ticket.report_template`.
- Можно передать `custom_template` прямо в запросе на генерацию отчета.
- Рендерер основан на Jinja2 `SandboxedEnvironment`.

### Share links

- Share-link ведет на публичный reviewer-view без аутентификации.
- На share-view раскрываются данные тикета, список артефактов и сообщения.

### Notifications

- Лента `GET /api/notifications` показывает `TicketEvent`.
- Для customer это события по его кейсам.
- Для support это события по тикетам, где он назначен `agent_id`.

## Запуск

Из корня репозитория:

1. При необходимости поправить [servicedesk/app/.env](/home/eliseev/ctf/cybernsk-2026-finals/services/servicedesk/servicedesk/app/.env:1).
2. Поднять стек:

```bash
docker compose -f servicedesk/docker-compose.yml up -d
```

Проверка:

```bash
curl http://localhost:8080/health
```

Ожидаемый ответ:

```json
{"ok": true, "service": "servicedesk"}
```

`app` в compose получает настройки через `env_file: app/.env`. При локальном
запуске из каталога `servicedesk/app` тот же файл подхватывается самим
`pydantic-settings`.

