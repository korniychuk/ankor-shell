---
id: 013
type: task
status: done
created: 2026-10-08
---

# 013 — `*-many`: ни один хост не пропадает из вывода молча

## Повод

Оператор запустил `ak.sudo.remote-lend-many` на 6 хостах. Два из них в этот момент не резолвились (`ssh: Could not resolve hostname vps-echo.example.internal` — MagicDNS-имя менялось). На экране остались только 4 зелёные строки ✔: ни ✘ по двум хостам, ни итоговой строки, ни счётчика недоступных. Требование: lend на всех рабочих хостах, по каждому нерабочему — красная строка с причиной (DNS, недоступен, auth, нет ankor-shell, canary, таймаут…), итог со счётчиками, код возврата ≠ 0 при любом промахе; число строк-результатов = числу хостов (дубли — с пометкой). То же проверить в `remote-revoke-many`, `remote-status-all`.

Профиль: J1 (локальные правки вывода, понятный контракт) · V0 (всё проверяется fake-ssh тестом локально) · R2 (инструмент, которым пользуются все сессии) — сделано в сессии, тесты в репо.

## Диагноз

- Путь «хост не резолвится → probe rc 255 → `unreachable` → ✘ в сводке» в коде на `bf1c9dc` **работает**: воспроизведено fake-ssh и настоящим ssh на несуществующих именах, в bash и zsh, интерактивно через pty, с вводом пароля — каждый хост получает строку, итог `N lent / M failed`, rc 1.
- **Единственный путь, дающий «только ✔ и тишину»** — прерывание после старта lend (подводный камень 12 задачи `00f`: «Ctrl-C после старта lend — сводки нет»). `__AK_SUDO_MANY_ON_INT` (`features/sudo-remote-many.sh:26` на `bf1c9dc`) делал `kill` джобов и `exit 130` без сводки: уже напечатанные ✔ оставались, все ещё не завершившиеся хосты исчезали. Воспроизведено тестом: `✔ ok-a`, затем только `rc=130`, хоста `slow-b` в выводе нет.
- Почему оператор нажал бы Ctrl-C: хост, у которого DNS/connect **висит** (а не падает сразу), держит сводку до дедлайна lend — 45 с (`ConnectTimeout` не покрывает DNS) — без единого слова на экране. Выглядит как зависание после зелёных строк.
- Сопутствующее: причина ✘ для любого rc 255 была `unreachable (ssh rc=255)` — DNS не отличался от отказа; в `status-all` и 124, и 255 печатались как `unreachable (timeout)`; дубли хостов отбрасывались молча; в `revoke-many` хост без записанного `.rc` классифицировался как `outdated`; в zsh без tty печаталось `device not configured: /dev/tty`.

## Фикс

- **Ctrl-C после старта lend печатает сводку**: `__ak.sudo.many.onInterrupt` (вызов из INT-трапа) помечает хосты без результата `interrupted before its result — state UNKNOWN, check: ak.sudo.remote-status <host>`, печатает ✘-блок и итог, rc 130. До старта lend — `interrupted before any lend — no host was changed.` Флаг `summaryArmed` в `__ak.sudo.many.run`.
- **Подсказка ожидания**: если хосты не ответили за 5 с — один раз в stderr `… still waiting for <hosts> (deadline 45s; Ctrl-C prints the summary now)`.
- **Итог lend-many**: `N lent / U unreachable / S skipped / F failed (T hosts)`; хост без записанного результата — ✘ `no result recorded — state UNKNOWN` (класс `missing`, раньше молча `failed`). Сумма счётчиков = T по построению.
- **Причина недоступности** — общий чистый `__ak.sudo.remote.sshFailReason` (`features/sudo-remote.sh`): `hostname does not resolve (DNS)`, host key, `ssh auth failed`, `connection refused`, `no route to host`, `connect timed out`, `unreachable (timeout — DNS or connect hung)`, иначе `unreachable (ssh rc=N)`. Используется в lend-many, revoke-many/all и status-all.
- **Дубли**: `__ak.sudo.remote.parseHosts` пишет предупреждение `duplicate host 'x' ignored — it is handled once.` (lend-many, revoke-many).
- `revoke-many`: нет `.rc` → `failed (rc=none recorded)`; `status-all`: нет `.rc` → `no result (poll job died) — state UNKNOWN`, в счётчике unreachable.
- Тихая проверка `/dev/tty` в zsh без терминала.

## Проверка

- `tests/sudo-remote.test.sh` (новый): fake ssh по префиксу имени — `nores-*` (не резолвится, rc 255), `hang-*` (висит до дедлайна), `noak-*`, `old-*`, `denied-*`, `slow-*` (lend висит), `ok-*`. В bash **и** zsh: одна строка на хост, причины, итог, rc; Ctrl-C во время висящего lend → подсказка ожидания, ✘ `interrupted`, итог, rc 130; revoke-many и status-all — те же инварианты. **62/62** на фиксе; на коде `bf1c9dc` — 24 провала (итог, DNS-причина, дубли, Ctrl-C).
- `bash -n` / `zsh -n`, `shellcheck -x` — новых замечаний нет (8 старых SC2154 про `AK_COLOR_*` из `sdk/shell.sh`), `bash tests/inet-check.test.sh` зелёный.
- Живьём (оператор, по желанию): `ak.sudo.remote-lend-many 5 nonexistent-alias.invalid` — без пароля и без касания хостов: ✘ `hostname does not resolve (DNS)`, `0 lent / 1 unreachable / 0 skipped / 0 failed (1 hosts)`, rc 1.

## Ход выполнения

Сделано 2026-10-08 в основной ветке. Хостов фикс не касается (вся логика — на ноутбуке), раскатка на флот не нужна.
