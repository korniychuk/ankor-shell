---
id: 00a
type: backlog
status: backlog
created: 2026-07-05
---

# 00a — Генератор документации: Rust + tree-sitter-bash → GitHub Pages

## Задача
Собственный CLI-генератор документации из doc-комментариев (канон 002) с обязательной фичей, которой нет ни у одного существующего инструмента: **ссылка с каждой функции на строку исходника в GitHub**. Реализация сайта — развитие backlog 001.

## Желаемый результат
- Rust CLI (в `tools/akdoc/` этого репо): парсит `*.sh` через tree-sitter-bash (crate 0.25+, first-party), извлекает `function_definition` + предшествующий блок комментариев + номера строк (`node.start_position().row`).
- Эмитит Markdown per-module: явные стабильные анкоры `### ak.str.replace() { #ak.str.replace }` (attr_list) + `[source](https://github.com/<owner>/ankor-shell/blob/${GITHUB_SHA}/sdk/str.sh#L42)` — immutable permalinks; опционально JSON (serde) для будущих потребителей (например, `-h/--help` из комментариев — старый TODO).
- Сайт: mkdocs-material (анкоры, поиск, `toc.permalink`) — либо mdBook, если хотим 100% Rust-тулчейн; решить на design-этапе.
- GitHub Actions: build генератора (cargo, кэш) → генерация md → deploy на GitHub Pages.
- Валидация: генератор падает с внятной ошибкой на doc-комментарии вне канона 002 → сам служит линтером формата (включить в CI из 003).

## Контекст / зацепки
- Research-отчёт по экосистеме (июль 2026): shdoc v1.4 (gawk, ожил в 2026, но фиксированный словарь тегов `@arg`/`@stdout` и НЕ эмитит номера строк), shellman/mkdocstrings-shell (чужой синтаксис, без source-links), bashdoc-rust (полумёртв). Вывод: source-line-links не делает никто; кастомный парсер неизбежен, tree-sitter делает его надёжным. Полный отчёт со ссылками сохранить в `docs/research/` при взятии в работу.
- Fallback-вариант (если Rust покажется overkill): патч shdoc ~15 строк (алиасы тегов + захват `NR` → source-link через `-v baseUrl=...`). Осознанно отклонён в пользу Rust: владение форматом, JSON, надёжность грамматики vs regex, интерес к Rust.
- Связь: 001 (сайт-обёртка), 002 (канон формата — prerequisite), 009 (комментарии приведены к канону).

## Открытые вопросы
- Куда класть сгенерированный md: артефакт CI (не коммитить) vs `docs/api/` в репо?
- Версионирование доков (latest only vs по тегам)?
- Имя утилиты: `akdoc`?
