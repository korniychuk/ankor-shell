---
id: 00f
type: task
status: planned
created: 2026-09-26
---

# 00f — `ak.sudo.remote-lend-many`: один пароль → lend на нескольких хостах, со сводкой

## Повод

Оператор регулярно открывает окно на нескольких VPS подряд, где sudo-пароль одинаковый:

```bash
ak.sudo.remote-lend vps-alpha 20; ak.sudo.remote-lend vps-bravo 20; ak.sudo.remote-lend vps-charlie 20
```

Три ssh-сессии, три ввода одного и того же пароля, итог размазан по выводу. Нужна одна команда: пароль вводится **один раз** (скрыто, под звёздочками, вставка из буфера работает), lend идёт на все хосты, в конце — сводка.

## Желаемый результат

```bash
ak.sudo.remote-lend-many 20 vps-alpha vps-bravo vps-charlie   # 20 минут
ak.sudo.remote-lend-many vps-alpha vps-bravo                  # дефолт lend (30m)
ak.sudo.remote-lend-many 20 vps-alpha,vps-bravo               # запятые тоже принимаются
```

```
sudo password for 2 hosts (vps-alpha, vps-charlie): ************

✔ vps-alpha    20m  until 14:32:05             lent
✔ vps-bravo    20m  until 14:32:06             re-lent, no password (was 14:20:11)
✔ vps-charlie  20m  until 2026-09-27 00:12:07  lent
✘ vps-delta    password rejected
    sudo: 1 incorrect password attempt
✘ vps-echo     unreachable (ssh rc=255)
    ssh: connect to host vps-echo.example.internal port 22: Operation timed out

3 lent / 2 failed
```

- Успешные — сверху, зелёным, в порядке ввода. Остаток — в минутах (округление до ближайшей), дедлайн — `HH:MM:SS` в **локальной** зоне оператора; если дедлайн не сегодня — ещё и дата `YYYY-MM-DD`. Колонка выровнена.
- Неудачные — ниже, красным: причина одной фразой + до 5 последних значимых строк вывода хоста с отступом (без шума `bash -i`: `no job control`, `cannot set terminal process group`).
- Окно, которое re-lend **укоротил** (было дольше, чем now+N), помечается жёлтым: `re-lent — window SHORTENED from 15:40:00`.
- Цвета — только если stdout это tty (как в `ak.sudo.remote-status-all`).
- Код возврата: `0` — все хосты успешны, `1` — хотя бы один неуспех или ошибка использования, `130` — отмена на вводе пароля.

## Дизайн

### 1. Аргументы

- `$1` целиком из цифр → минуты; валидация `__ak.sudo.validMinutes` (1..1440). Число вне диапазона — ошибка, **не** имя хоста.
- Нет числа → `AK_SUDO_DEFAULT_MINUTES`. Новая константа в `features/sudo.sh` (`declare -r AK_SUDO_DEFAULT_MINUTES=30`), ею заменяются литералы `30` в `ak.sudo.lend`. Минуты передаются хостам **явно**, чтобы все окна были одинаковыми, даже если на каком-то хосте дефолт другой версии.
- Остальные аргументы — хосты: разбить по запятым и пробелам, пустые выбросить, дубли убрать с сохранением порядка. Хостов нет → usage.
- Хост из одних цифр → ошибка `minutes go FIRST: ak.sudo.remote-lend-many 20 h1 h2`. Это ловит мышечную память от `ak.sudo.remote-lend <host> <min>`, где порядок обратный.
- Хост начинается с `-` или содержит символы вне `[A-Za-z0-9._@-]` → ошибка. Хосты идут в argv `ssh` после `--`, но проверка всё равно дешёвая.

### 2. Поток выполнения

1. **Probe (параллельно, без пароля).** Та же механика, что у `ak.sudo.remote-status-all`: `ssh -T -n -o BatchMode=yes`, `ak.sh.timeout`, tmp-каталог под EXIT/INT/TERM trap. Общий код выносится в `__ak.sudo.remote.pollAll` (им пользуются обе команды). Удалённая команда собирается локально:
   `command -v ak.sudo.status >/dev/null || exit 127; ak.sudo.status --porcelain; sudo -n true 2>/dev/null && echo nopasswd=1 || echo nopasswd=0`.
2. **Классификация по probe**:
   - `124`/`255` → ✘ unreachable (с ssh stderr);
   - `127` → ✘ ankor-shell not installed;
   - porcelain без `lend_api=1` → ✘ `ankor-shell outdated — run the fleet update first`;
   - `granted=1` или `nopasswd=1` → «пароль не нужен» (запоминаем прежний `deadline_epoch` для сводки);
   - иначе → «нужен пароль».
3. **Пароль — только если он кому-то нужен.** Все хосты уже с грантом → запроса нет вообще. Запрос: `ak.sh.readSecret` (§4) с перечнем хостов, которым пароль нужен. Пустой ввод / Ctrl-C / нет tty → отмена **всего**, ни один хост не тронут (запрос идёт до любого lend).
4. **Canary.** Первый хост из «нужен пароль» — отдельно, **до** остальных; параллельно с ним идут хосты «пароль не нужен». Если canary вернул `password rejected` → остальные «нужен пароль» помечаются `skipped — password rejected on <canary>` и **не получают пароль**. Если canary отвалился по другой причине (сеть, таймаут, requiretty) → canary-ом становится следующий хост. Зачем — см. подводный камень №1.
5. **Остальные** «нужен пароль» — параллельно. Сразу после того как пароль записан в пайп последнего ssh-задания — `unset` переменной в родителе.
6. **Сводка** (§5) → код возврата.

Удалённая команда lend (собирается локально, минуты уже провалидированы):

```bash
ssh -T -o BatchMode=yes -o ConnectTimeout=… -- HOST \
  "bash -lic 'command -v ak.sudo.lend >/dev/null || exit 127; ak.sudo.lend --password-fd 3 20; rc=\$?; ak.sudo.status --porcelain; exit \$rc' 3<&0 0</dev/null"
```

stdin ssh — это пайп с паролем (или пустой пайп для хостов «пароль не нужен»). Внешний login-shell хоста переносит его на **fd 3**, а stdin самого `bash -lic` делает `/dev/null`. Итоговый `deadline_epoch` берётся из porcelain-строки **после** lend, поэтому сводка показывает реальное состояние, а не ожидание. Таймаут на хост — `AK_SUDO_REMOTE_MANY_TIMEOUT` (дефолт 45 с: `systemctl daemon-reload` бывает медленным).

`StrictHostKeyChecking` **не** ослабляется до `accept-new` (как в status-all): при lend хосту уходит пароль, и TOFU на ещё не виденном ключе отдал бы его MITM. Неизвестный ключ → BatchMode падает → ✘ `host key not in known_hosts — ssh HOST once first`.

### 3. Удалённая сторона: `ak.sudo.lend --password-fd <n>`

Новый необязательный режим в `ak.sudo.lend` (`features/sudo.sh`):

- `--password-fd <n>`, где `n` из `3..9`, затем необязательные минуты. Без флага поведение **не меняется**, `$0`-guard остаётся.
- Если `sudo -n true` уже проходит (грант / NOPASSWD / кэш) — fd не читается вообще.
- Иначе `IFS= read -r -u "$n" pw`. Пусто → код `AK_SUDO_RC_NO_PASSWORD`. Затем:
  `err="$( { printf '%s\n' "${pw}" | LC_ALL=C sudo -S -p '' -v; } 2>&1 > /dev/null )"`, и сразу `unset pw`.
  `printf` встроенный, пароль не попадает в argv (`ps`). `-p ''` глушит приглашение. Без pty ничего не отражается эхом.
- Классификация по `rc` + `err` (`LC_ALL=C` делает сообщения sudo стабильными):
  `incorrect password|Sorry, try again` → `AK_SUDO_RC_BAD_PASSWORD`;
  `a terminal is required|must have a tty|requiretty` → `AK_SUDO_RC_NEEDS_TTY`;
  прочее → `1`.
- После `-v` — проверка `sudo -n true`. Не прошла → `AK_SUDO_RC_NO_CACHE` («password accepted, but the sudo credential cache is not reusable here — timestamp_timeout=0 / timestamp_type»). Дальше lend идёт штатно: кэша хватает на запись drop-in, а после неё работает уже `NOPASSWD`.
- Коды — константы в `features/sudo.sh`, вне зарезервированных `1/124/126/127/130/255`: например `20..23`. Локальная сторона классифицирует по коду, а stderr показывает только как пояснение.
- На время работы с паролем — `set +x` (bash: `local -`; zsh: `setopt localoptions noxtrace`), иначе xtrace напечатает пароль.
- `ak.sudo.status --porcelain` дописывает поле `lend_api=1` (маркер возможности, §2). Парсеры porcelain обязаны игнорировать незнакомые поля; `remote-status-all` уже так делает — проверить и зафиксировать это в doc-комментарии.

### 4. Локальный ввод: `ak.sh.readSecret` (`sdk/shell.sh`)

Общая утилита (не sudo-специфичная): `pw="$(ak.sh.readSecret 'prompt: ')"`. Command substitution — это fork и пайп, без файла; nameref не нужен, в zsh его нет.

- Читает из `/dev/tty`, приглашение и `*` пишет в `/dev/tty` (stdout остаётся чистым для захвата). Нет `/dev/tty` → `return 1` с ошибкой.
- На весь цикл: `stty -echo -icanon min 1 time 0` с сохранением `stty -g`, восстановление — в trap на EXIT/INT/TERM и на всех путях выхода. **Не** `read -s` на каждый символ: `-s` включает эхо обратно между вызовами, и быстро вставленные символы в этот зазор уходят на экран открытым текстом.
- Посимвольное чтение: bash — `read -r -n1 -d ''`, zsh — `read -r -k1`; ветвление через `ak.sh.isZsh`. Enter (`\r`/`\n`) — конец; Backspace (`\x7f`/`\b`) — удалить символ и стереть `*`; Ctrl-U — очистить; Ctrl-C → восстановить tty, `return 130`. Маркеры bracketed paste `\e[200~`/`\e[201~` вырезать; прочие ESC-последовательности игнорировать.
- `*` на символ; в конце — перевод строки. `set +x` локально, как в §3.
- Своя история у неё отсутствует (это не zle/readline), в `HISTFILE` ничего не попадает.

### 5. Сводка (чистые функции, testable-first)

- `__ak.sudo.many.formatDeadline <deadlineEpoch> <nowEpoch>` → `20m  until 14:32:05` или `… until 2026-09-27 00:12:07`, если локальная дата дедлайна ≠ локальной дате `now`. Даты через BSD `date -r` / GNU `date -d @` (как в `__ak.sudo.epochClock`).
- `__ak.sudo.many.classify <probeState> <rc> <porcelain>` → `ok|relent|shortened|bad_password|skipped|needs_tty|no_cache|outdated|no_ak|unreachable|timeout|failed`.
- `timeout` посреди lend → ✘ `timed out — state UNKNOWN, check: ak.sudo.remote-status HOST`.
- `now` передаётся параметром, чтобы формат можно было проверить без живых хостов.

### 6. Автодополнение

`completions/zsh/ak.sudo.remote.zsh` и `completions/bash/ak.sudo.remote.bash`: добавить `ak.sudo.remote-lend-many`.

- Позиция 2 — пресеты минут `15 30 60 120` **и** хосты.
- Позиции ≥3 — хосты, кроме уже набранных.
- zsh — с описаниями `alias → user@hostname` из `ak.ssh.hosts.described`, bash — просто имена.
- Канонический разделитель — пробел; запятые принимаются, но дополнение после запятой не делаем.

### 7. Раскладка по файлам

- `features/sudo.sh` уже 819 строк (🟠). Весь remote-раздел (`__ak.sudo.remote.exec`, `remote-lend/revoke/status/status-all`) переезжает в новый **`features/sudo-remote.sh`**, туда же — `remote-lend-many` и `__ak.sudo.remote.pollAll`. `index.sh` подключает его сразу после `sudo.sh`.
- Цель — оба файла ≤500 непустых строк. Если `sudo-remote.sh` не укладывается, lend-many со сводкой уходит в `features/sudo-remote-many.sh`.
- Перенос — **отдельным коммитом, без изменения поведения** (чистый move), фича — следующими.
- Шапка `features/sudo.sh`: в `@example` добавить lend-many.
- `CLAUDE.md` репо: в таблицу модулей добавить `features/sudo*.sh`, сейчас их там нет.

## Подводные камни

1. **Неверный пароль × весь флот = блокировка аккаунта.** `pam_faillock` (часто `deny=3`) считает неудачные попытки на **каждом** хосте. Повторённая пара запусков с опечаткой залочила бы sudo на всех VPS разом. Защита — canary (§2.4): неверный пароль тратит **одну** попытку на одном хосте. `sudo -S` получает ровно одну строку, после EOF повторов нет.
2. **Re-lend ставит окно в now+N, а не прибавляет N.** Осталось 50 минут, запрос 20 → окно **сокращается** до 20. Семантика `ak.sudo.lend` сохраняется; сокращение подсвечивается жёлтым в сводке.
3. **Обратный порядок аргументов** относительно `remote-lend <host> <min>` — ловится проверкой «хост из цифр» (§1).
4. **rc-файлы удалённого шелла могут съесть stdin с паролем** — поэтому пароль идёт через fd 3, а stdin `bash -lic` = `/dev/null`.
5. **Эхо пароля через pty.** С `ssh -t` пароль, пришедший до того, как sudo выключит эхо, вернулся бы в вывод. Поэтому `-T` (без pty) + `sudo -S`.
6. **Кэш sudo без tty.** `-v` и последующий `sudo` должны делить timestamp; без tty он привязан к ppid. `timestamp_timeout=0` или экзотический `timestamp_type` это ломают — детектируется проверкой `sudo -n true` (§3) и **обязательно** проверяется вживую.
7. **`Defaults requiretty` / PAM с 2FA** — `-S` без tty там невозможен → ✘ с понятной причиной; такой хост — только через обычный `remote-lend`.
8. **Хостам нужна свежая ankor-shell.** До раскатки новой версии хосты помечаются `outdated` (маркер `lend_api`). Раскатать до первого боевого использования.
9. **Память процесса.** Строки bash/zsh невозможно затереть — `unset` освобождает, но не обнуляет. Лучшее, что доступно: не экспортировать (иначе `/proc/<pid>/environ`), не писать в файлы, `unset` сразу после последнего использования, xtrace выключен.
10. **Буфер обмена.** Вставка работает, но история буфера (Raycast) сохранит пароль, если копировать его как обычный текст. KeePassXC помечает копию как concealed (`org.nspasteboard.ConcealedType`), такие менеджеры её не пишут, и сам очищает буфер. Копировать только из KeePassXC.
11. **Не запускать через агента** (`! …` в Claude Code): там нет tty → `readSecret` откажет, и это правильно. Пароль никогда не должен попадать в контекст агента.
12. **Ctrl-C после старта lend** — часть хостов уже с грантом, сводки нет. Не опасно (auto-revoke), но нужно `ak.sudo.remote-status-all`.
13. **SSH-ключ с passphrase не в агенте** → BatchMode падает сразу (✘ `ssh auth failed`), а не висит на запросе.
14. **Разные пароли** на части хостов → там ✘ `password rejected` (одна попытка на хост), остальные успешны. Это ожидаемо.

## План

1. **Move**: remote-раздел `features/sudo.sh` → `features/sudo-remote.sh`, source в `index.sh`. Поведение не меняется, `bash -n`/`zsh -n` зелёные. Отдельный коммит.
2. `AK_SUDO_DEFAULT_MINUTES` + константы кодов `AK_SUDO_RC_*`; `ak.sudo.lend --password-fd`; `lend_api=1` в porcelain.
3. `ak.sh.readSecret` в `sdk/shell.sh`.
4. `__ak.sudo.remote.pollAll` (рефактор `remote-status-all` на него) + `ak.sudo.remote-lend-many` + чистые форматтеры/классификатор.
5. Автодополнение zsh + bash.
6. Шапки/doc-комментарии, `CLAUDE.md` репо.
7. **Живая проверка** (оператор + основная сессия, не executor): см. ниже.
8. **После** живой проверки — `srv-ankor-vps` (раздел ниже), закрыть задачу.

Шаги 1–6 — это работа для `codex-agent.sh`: только git-дерево. Шаги 7–8 — в основной сессии.

## Проверка

Статически: `bash -n` и `zsh -n` на всех затронутых файлах, `shellcheck` на новых функциях. Чистые функции — прогон с фиксированным `now`: дедлайн сегодня / завтра (через полночь) / округление минут / сокращённое окно; разбор аргументов: `20 a b`, `a,b c`, `a 20` (ошибка), `0 a` / `1441 a` (ошибка), дубли.

Вживую (после раскатки ankor-shell на тестовые хосты):

| # | Сценарий | Ожидание |
|---|---|---|
| 1 | 3 хоста, нужен пароль, верный | один запрос, 3 ✔, дедлайны с секундами |
| 2 | один хост уже с грантом | для него `re-lent, no password`, в запросе его нет |
| 3 | все с грантом | запроса пароля нет вовсе |
| 4 | неверный пароль | ✘ canary `password rejected`, остальные `skipped`; в `journalctl`/`faillock` остальных хостов попыток нет |
| 5 | несуществующий alias / лежащий хост | ✘ unreachable, остальные ✔ |
| 6 | хост со старой ankor-shell | ✘ outdated |
| 7 | Ctrl-C и пустой Enter на запросе | ничего не изменено, эхо терминала восстановлено (`stty -a` → `echo icanon`) |
| 8 | вставка из KeePassXC | число `*` = длине, lend успешен |
| 9 | 1440 минут | в сводке есть дата |
| 10 | утечки | во время прогона `ps -axww` локально и `ps -eww` на хосте не содержат тестового пароля; после — tmp-каталог удалён; с включённым `set -x` пароля в трассе нет; auth.log хоста его не содержит |

Для п.10 — временный тестовый пароль на тестовом хосте, не боевой.

## Документация в `srv-ankor-vps` (шаг 8)

Только после того, как команда проверена вживую: агенты там не должны ссылаться на несуществующее.

- `CLAUDE.md`, раздел «sudo on the VPSes — PROBE IT»: в блок команд добавить строку

  ```
  ak.sudo.remote-lend-many [minutes] <host-alias>...  # same password everywhere: ONE hidden prompt (only if a host needs it),
                                                      # canary-checked, parallel; green/red per-host summary with deadlines
  ```

  В пункт «Need unattended sudo → ask the operator…» добавить: нужны несколько хостов → просить `ak.sudo.remote-lend-many [min] h1 h2 …`. Пароль агент никогда не запрашивает и команду сам не запускает — ввод пароля только у оператора.
- `docs/MESH-OPERATIONS-RUNBOOK.md` (строка про `ak.sudo.remote-lend`, ~283) — одно упоминание lend-many для многохостовых окон.
- В `srv-ankor-vps` реальные имена хостов допустимы (приватный репо), в `ankor-shell` — только плейсхолдеры.

## Вне скоупа

- `ak.sudo.remote-revoke-many` — очевидная пара, но отдельной задачей, если понадобится.
- Хранение пароля между вызовами (keychain, агент) — сознательно нет.
