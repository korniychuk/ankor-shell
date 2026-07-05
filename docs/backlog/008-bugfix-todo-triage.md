---
id: 008
type: backlog
status: backlog
created: 2026-07-05
---

# 008 — Багфиксы + триаж 55 TODO

## Задача
Исправить известные баги и разгрести все 55 TODO-маркеров: каждый — либо fix сейчас, либо оформленная backlog/idea-запись, либо осознанное удаление. После задачи в коде остаются только TODO со ссылкой на doc-задачу.

## Желаемый результат
- Баги исправлены:
  - `ak.sh.isInteractive` (`sdk/shell.sh:332`) — `return [[ ... ]]` невалиден синтаксически;
  - `ak.sh.commandExists` (`sdk/shell.sh:168-174`) — нет явного success-пути, код возврата хрупкий;
  - `die`/`param.required` `exit` из интерактивной сессии (решается в 005, здесь — проверить все call-sites);
  - `printf` с переменным format-string (`sdk/str.sh:32,66,124`, SC2059) и `eval "echo {1..$n}"`;
  - unquoted expansions (`sdk/shell.sh:156,249,277,299`, `index.sh:50`);
  - cals.sh: обёртки не регенерируются при изменении шаблона/`AK_SCRIPT_PATH` (создаются только если файла нет) — добавить механизм инвалидации (версия/hash шаблона в обёртке); ветка missing-prefix только warn'ит без `return` (`cals.sh:31`); word-split в `find | for` циклах.
- Дизайн-бэклог из шапки `index.sh` (27 TODO, строки 3–44) вынесен в `docs/ideas/` (по записи на идею или одним списком с приоритетами) — из кода удалён.
- Кластер TODO в `sdk/git.sh` (16 шт., redate-хелперы) — триаж: часть закрывается 006 (validation), остальное — в ideas или удалить.
- Perl-зависимость (`str.sh`, `git.sh`) — оценить и оформить отдельной идеей (не чинить здесь).
- Итоговая таблица триажа в task-доке: TODO → решение.

## Контекст / зацепки
- Полный инвентарь TODO по файлам — в отчёте разведки, продублирован в `ankor/hardening-ref-notes.md`.
- Часть TODO закрывается соседними задачами: arg-checking → 006, «Check docker installed» → 006 (`cmdExist`), «min bash version» → 007 (semver), notifier/dialogs (macos) → ideas.

## Открытые вопросы
- `git filter-branch` устарел (upstream рекомендует filter-repo) — мигрировать или оставить? Скорее отдельная идея.
