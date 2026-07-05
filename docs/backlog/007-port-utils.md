---
id: 007
type: backlog
status: backlog
created: 2026-07-05
---

# 007 — Портирование системных утилит

## Задача
Перенести в ankor-shell отобранные generic-утилиты из reference-библиотеки (адаптировав под `ak.*` нейминг и конвенции 002). Утилиты, специфичные для чужой инфраструктуры (Nx Cloud, S3, Node-хинты), НЕ переносим.

## Желаемый результат
- `ak.inet.isTcpPortOpen port [host]` — dependency-free проба порта через `/dev/tcp` (валидация 1–65535, FD-гигиена); `ak.inet.waitTcpPortOpen port [host] [timeout]` — poll 250ms, ms-точный учёт, 0 = infinite. Заодно закрыть TODO `sdk/inet.sh:147` («add timeout, method too slow»).
- `ak.sh.pollPid pid` — ожидание НЕ-дочернего процесса через `kill -0` (nohup/disown/чужой shell); валидация PID, graceful при уже-мёртвом.
- `ak.sh.waitForPids pids...` — fan-in параллельных дочерних задач: при первом падении убивает выживших и `die` (код 20).
- `ak.semver.satisfies version spec` (+ `ak.semver.split`) — компаратор exact/tilde/caret; закрывает TODO `index.sh` «min bash version check» и пригоден для version-гейтинга инструментов.
- `ak.sh.hasShellFn name` (function/alias/builtin через `type`) — дополнение к исправленному `ak.sh.commandExists` (008).
- Bootstrap-скелет: strict mode + double-import guard (sentinel-функция + `SCRIPT_PATH`) — применить к `index.sh` (идемпотентный повторный source) и шаблону CaLS-обёрток, не ломая zsh-путь.
- Всё — с doc-комментариями канона 002 и тестами (004).

## Контекст / зацепки
- Точные механизмы образцов и их слабые места: `ankor/hardening-ref-notes.md`.
- Порядок сорсинга модулей в `index.sh` важен (цвета/shell — первыми): зафиксировать комментарием.

## Открытые вопросы
- `/dev/tcp` — bashism: для zsh-пути нужен fallback (`zsh/net/tcp` или ограничить bash'ем с явной ошибкой).
- Расширять ли spinner'ами/retry-with-backoff (в образце их нет, идея на вырост) — отдельной идеей в docs/ideas.
