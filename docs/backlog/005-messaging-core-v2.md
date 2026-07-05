---
id: 005
type: backlog
status: backlog
created: 2026-07-05
---

# 005 — Messaging core v2: вывод, цвета, ERR trap

## Задача
Модернизировать ядро вывода сообщений в `sdk/shell.sh` по лучшим практикам reference-библиотеки, исправив при этом её слабости (безусловные цвета) и наши хазарды (`exit` из sourced-контекста).

## Желаемый результат
- `ak.sh.ok/warn/err/die` v2: единый формат `${Bold}${label}: ${color}${msg}`, `ok` → stdout, `warn/err` → stderr; `err` авто-захватывает последний exit-код (`$?` читается первой строкой) и печатает `Last Error Code: N` при ненулевом.
- `ak.sh.die`: hook-паттерн — если у вызывающего определена функция `ak_print_help`, печатать её перед выходом; **критично**: в интерактивном sourced-контексте `return`, а не `exit` (сейчас `die`/`param.required` убивают всю сессию пользователя).
- Цвета: gating через `[[ -t ]]` + поддержка `NO_COLOR` (в reference-библиотеке этого нет — это её главная слабость, не копировать); решить судьбу TODO `AK_COLOR_*` → `AK_CLR_*` (алиасы для обратной совместимости).
- ERR trap со stack trace: `__ak.sh.errorTrap` — exit-код, `$BASH_COMMAND`, PWD, timestamp, покадровый обход `caller $frame`. Устанавливается ТОЛЬКО в скриптах (CaLS-обёртки, standalone), НЕ в интерактивном shell.
- `ak.sh.indent [n]` — отступ каждой строки stdin (sed-padding) для вложенного вывода.
- envsubst-темплейтинг сообщений об ошибках (плейсхолдеры `${_name}` в single-quoted кастомных сообщениях) — без eval-инъекций.

## Контекст / зацепки
- Детальный разбор механизмов-образцов (код ERR trap, авто-захват `$?` через `_LAST_ERR_CODE`, help-hook): `ankor/hardening-ref-notes.md`.
- Текущие функции: `sdk/shell.sh:214-278`; сейчас всё пишет в stderr, включая `ok`.

## Открытые вопросы
- Совместимость сигнатур: `ak.sh.ok msg [status]` уже используется — сохранить порядок аргументов.
- zsh: `caller`/`BASH_COMMAND`/`ERR` trap ведут себя иначе — trap только для bash-скриптов или городить zsh-ветку?
