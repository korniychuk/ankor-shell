---
id: 010
type: task
status: in-progress
created: 2026-09-26
---

# 010 — `ak.sudo.remote-revoke-many` / `remote-revoke-all` + фикс canary в lend-many

## Повод

1. Живая проверка `00f` (тест 4, неверный пароль) показала, что пароль ушёл на **три** хоста вместо одного: на части флота sudo пишет `Authentication failed, try again.` вместо `Sorry, try again`, классификатор это не знает → rc=1 → «отказ по другой причине» → canary переезжает на следующий хост. Именно тот сценарий, ради которого canary и придуман (faillock).
2. Пара к `remote-lend-many`: закрыть окна на нескольких хостах одной командой и на всём флоте разом — параллельно, со сводкой.
3. Документация для агентов в `srv-ankor-vps` должна описывать все три команды (шаг 9 задачи `00f` расширяется).

## Дизайн

### Фикс canary (`features/sudo.sh`, `features/sudo-remote-many.sh`)

- `__ak.sudo.classifyAuthError`: `incorrect password|Sorry, try again|Authentication failed` → `AK_SUDO_RC_BAD_PASSWORD`.
- Политика canary в `__ak.sudo.many.lendRound`:
  - **доказан** (`ok|relent|shortened|no_cache`) → пароль уходит волне; `no_cache` = пароль принят, кэш не переиспользуется — это доказательство;
  - **отклонён** (`bad_password`) → остальные «нужен пароль» `skipped — password rejected on X`;
  - **не проверялся** (`unreachable|timeout|no_ak|outdated|needs_tty`) → следующий хост становится canary;
  - **любой другой провал** (`failed`, `grant_vanished`, `relent_other_password`, …) → пароль **не доказан**: остальные «нужен пароль» `skipped — password not proven on X (rc=N)`, волна «пароль не нужен» идёт без пароля. Консервативно: непонятный провал после отправки пароля не должен стоить попыток faillock на всём флоте.
- Косметика: у stderr sudo обрезаются ведущие пустые строки (`-p ''` печатает перевод строки перед сообщением) — в сводке не будет пустой строки после `ERROR:`.

### `ak.sudo.remote-revoke-many <host>...` (`features/sudo-remote.sh`)

- Хосты — как у lend-many (пробелы/запятые, дубли, валидация); разбор выносится в общий `__ak.sudo.remote.parseHosts`, `__ak.sudo.many.parseArgs` использует его.
- Параллельно через `__ak.sudo.remote.pollAll` (strict host key, как lend-many — пароль не передаётся, но и TOFU здесь ни к чему). Удалённая команда: `ak.sudo.status --porcelain` **до** revoke (что было), `ak.sudo.revoke`, `ak.sudo.status --porcelain` **после**, `exit rc`.
- Сводка в порядке ввода после завершения всех (revoke быстрый, потоковая печать не нужна): ✔ `revoked (was until HH:MM:SS)` зелёным; `no grant` серым; ✘ `still granted` / `unreachable` / `outdated` / `not installed` / `failed (rc=N)` красным + последние строки вывода. Итог `N revoked / M no grant / K failed`.
- Код возврата: 0 — все хосты обработаны (revoked или no grant), 1 — хотя бы один недоступен/провалился или ошибка использования.
- Таймаут на хост — `AK_SUDO_REMOTE_MANY_TIMEOUT` (45 с, `daemon-reload`).

### `ak.sudo.remote-revoke-all` (`features/sudo-remote.sh`)

- Без аргументов; хосты — `ak.ssh.hosts` (как `remote-status-all`). Та же сводка.
- Это отчёт по флоту, а не проверка списка: недоступные хосты — информация (как в `status-all`), код возврата 1 только при реальном провале revoke на достижимом хосте.

### Автодополнение

`revoke-many` — хосты минус уже набранные (любая позиция); `revoke-all` — без дополнения. zsh с описаниями, bash — имена.

### Документация

- `features/sudo.sh` шапка (`@example`), `CLAUDE.md` репо (строка `sudo-remote.sh`).
- `srv-ankor-vps`: `CLAUDE.md` раздел «sudo on the VPSes» и `docs/MESH-OPERATIONS-RUNBOOK.md` — lend-many / revoke-many / revoke-all (это шаг 9 задачи `00f`).

## План

1. Фикс canary + regex + trim stderr; коммит.
2. `parseHosts` + `revoke-many` + `revoke-all`; коммит.
3. Автодополнение; коммит.
4. Шапки, `CLAUDE.md`; коммит. Push.
5. Раскатка на флот (`scripts/ankor-shell-update.sh`) — regex/canary живут на хостах (`classifyAuthError`), revoke — тоже.
6. Живая проверка оператором: неверный пароль на 3 хостах → ровно **один** `password rejected`, остальные `skipped`; `revoke-many` на 2 хостах с грантом и 1 без; `revoke-all`.
7. Документация `srv-ankor-vps`, закрыть `00f` и эту задачу.

## Проверка

Статически: `bash -n`/`zsh -n`, source `index.sh` в обоих шеллах, shellcheck. Чистые функции: `classifyAuthError` на трёх формулировках; `parseHosts` (`a,b c`, `20 a` → ошибка, дубли, пусто → usage).
