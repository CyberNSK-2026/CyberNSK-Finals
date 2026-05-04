# TypeVault Vulnerabilities

## SCN-1: Weighted Ranking Sanitizer Bypass (SQLi)
- Компонент: `lib/typevault/gallery.ex`
- Суть: небезопасная интерполяция весов (`dw`, `rw`) в SQL при сортировке по популярности.
- итог: `UNION`-чтение `design_notes` из публичных проектов.

## SCN-2: Context Expansion Information Leak
- Компонент: `lib/typevault/export/context.ex`
- Суть: при совпадении gate-условия в ответ добавляется расширенный проектный объект, содержащий `design_notes`.
- итог: массовое извлечение флагов перебором `(mode, bias)`.

## SCN-3: Callback Redirect SSRF
- Компонент: `lib/typevault_web/controllers/font_controller.ex`
- Суть: callback-preview с follow-redirect до внутреннего endpoint.
- итог: чтение внутреннего `/api/internal/status` с утечкой `design_notes`.

## SCN-4: TVF Validator vs Rust FSM Desync
- Компоненты:
  - Elixir: `lib/typevault/tvf_validator.ex`
  - Rust NIF: `native/tvf_parser/src/lib.rs` (игрокам отдаем бинарный `.so`)
- Суть: различие трактовки потока байт валидатором и Rust FSM.
- итог: скрытая ветка в рендере `preview_draft` и извлечение `design_notes`.

