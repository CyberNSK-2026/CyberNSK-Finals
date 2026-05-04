# TypeVault

TypeVault — сервис управления шрифтовыми ассетами и проектами.
Реалистичный SaaS-продукт с аутентификацией, проектами, загрузкой шрифтов, превью, галереей и экспортом.

## Возможности

- Регистрация и управление профилем
- Создание приватных и публичных шрифтовых проектов
- Загрузка кастомных TVF-файлов
- Генерация превью и specimen через Rust NIF
- Публичная галерея с фильтрацией и сортировкой
- Экспорт с пользовательскими настройками

## Модель данных

- `users` — учётные записи
- `font_projects` — проекты; поле `design_notes` содержит авторские заметки
- `font_files` — загруженные TVF-файлы
- `project_members` — роли совместного доступа (viewer/editor)
- `project_events` — журнал событий проекта
- `export_presets` — именованные шаблоны экспорта

## Архитектура

Основной стек:
- Elixir + Phoenix 1.7 (web/API/auth/бизнес-логика)
- PostgreSQL (хранение данных)
- Rustler NIF в `native/tvf_parser` (парсинг TVF, рендеринг, валидация URL)

Ключевые модули:
- `lib/typevault/gallery.ex` — публичная галерея
- `lib/typevault_web/controllers/export_controller.ex` — экспорт
- `lib/typevault_web/controllers/font_controller.ex` — управление шрифтами
- `lib/typevault_web/controllers/internal_controller.ex` — внутренние endpoint-ы
- `native/tvf_parser/src/lib.rs` — Rust NIF: парсинг, рендер, URL-валидация

## Запуск

```bash
docker-compose up --build
```

Приложение будет доступно на `http://localhost:4000`.

## Service Validation

```
python3 checker/checker.py check  <host>
python3 checker/checker.py put    <host> <record_id> <record_value>
python3 checker/checker.py get    <host> <record_id> <record_value>
```

## TODO

- Пагинация и единый API response envelope
- Rate limiting на auth/export/gallery endpoint-ы
- Структурированные логи с request_id
- Метрики (latency, error rate, export throughput)
- Background job queue для тяжёлого рендера
- Индексы БД под основные API-паттерны
- Unit-тесты парсера и интеграционные тесты flow
