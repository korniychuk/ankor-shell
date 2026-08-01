---
id: 00b
type: task
status: ready
created: 2026-08-01
---

# 00b — `ak.sudo.remote-*`: удалённый lend/revoke/status + обзор по всем хостам, с автодополнением SSH

## Проблема

Одалживание sudo на удалённой машине сейчас выглядит так:

```bash
ssh -t vps-india 'bash -lic "ak.sudo.lend 20"'
ssh -t vps-golf "bash -lic 'ak.sudo.lend 15'"
```

Длинно, требует помнить точную схему двойного quoting (её ловушка описана в `features/sudo.sh:19-26` и закрыта guard'ом на `$0` в `features/sudo.sh:202`), имя хоста набирается руками. Плюс нет способа увидеть картину целиком: где сейчас открыт grant и надолго ли.

## Желаемый результат

```bash
ak.sudo.remote-lend vps-ind<TAB> 20     # grant на 20 минут
ak.sudo.remote-lend vps-golf  # дефолт удалённой стороны (30m)
ak.sudo.remote-status vps-bravo
ak.sudo.remote-revoke vps-india
ak.sudo.remote-status-all               # обзор по всем хостам сразу
```

`<TAB>` на позиции хоста даёт меню в том же виде, что уже настроено для `ssh` — alias слева, `user@hostname` справа через `→` (у оператора fzf-tab в tmux-попапе, то есть fuzzy-выбор):

```
vps-alpha  → deploy@vps-alpha.example.internal
lan-admin              → deploy@198.51.100.6
vps-bravo → deploy@203.0.113.10
```

`<TAB>` на второй позиции у `remote-lend` — подсказки `15 30 60 120`.

`ak.sudo.remote-status-all` — параллельный опрос всех хостов, состояние на момент вызова (никакого кэша):

```
vps-alpha   granted — 23m left (until 18:42)      ← зелёный
vps-bravo  no grant                              ← красный
lan-desktop              ankor-shell not installed             ← серый
vps-delta              unreachable (timeout)                 ← жёлтый
```

## Решения (приняты, не пересматривать)

- **Имена**: `ak.sudo.remote-lend` / `-revoke` / `-status` / `-status-all`. Дефис, а не третий уровень через точку. Короткий алиас в `config.sh` **не заводим** — `ak.su<TAB>` достаточно. (Отвергнуто: `asr` — занято `/usr/sbin/asr`, Apple Software Restore.)
- **ankor-shell на удалённой стороне** берём из remote rc через `bash -lic`. Отправку исходников по stdin не делаем: тянет полсдк зависимостями (`ak.sh.err`, `ak.os.type.*`) и конфликтует с `ssh -t` за stdin. YAGNI.
- **Минуты не дублируем**: аргумент не передан — шлём голый `ak.sudo.lend`, дефолт (30) применяет удалённая сторона. Единственный источник правды.
- **`user@hostname` для меню НЕ парсим сами** — берём из `ssh -G <host>` (эффективный конфиг с учётом `Include`, wildcard-блоков и наследования). Парсинг конфига остаётся только ради перечисления имён: `ssh -G` перечислять не умеет.
- **Цвета `status-all`**: зелёный — grant активен, красный — ankor-shell есть, но grant'а нет, серый — ankor-shell не установлен/команда недоступна, жёлтый — хост не ответил (таймаут/отказ). Четвёртый цвет добавлен сверх заказанных трёх осознанно: «недоступен» и «нет ankor-shell» — разные диагнозы, слипшись в один серый они врут.

## План

### 1. `sdk/ssh.sh` (новый модуль)

Отдельный SDK-модуль, а не приватная функция в `features/sudo.sh`: список хостов — не забота sudo-домена (Information Expert), и это первый кирпич под старый TODO `index.sh:38` («ak.ssh.save, ak.ssh.connect»).

**`ak.ssh.hosts()`** — печатает connectable-хосты, по одному в строке, отсортированные и дедуплицированные:
- вход по умолчанию `~/.ssh/config`; переопределение через `AK_SSH_CONFIG` (тестируемость);
- `Host` — регистронезависимо (ssh_config таков), разделитель пробелы **или** `=`;
- одна строка `Host` может нести несколько имён — брать все (**текущая `_ssh_hosts` в `~/.zshrc:63` это теряет** из-за `$` в regex);
- **отбрасывать** паттерны с `*`, `?` и негативные `!host` — не connectable-цели (у оператора это `Host *` и `Host 198.51.100.* lan-*`);
- **`Include`**: рекурсивно, относительные пути от `~/.ssh/`, с поддержкой glob (`Include conf.d/*`). У оператора есть `Include ~/.orbstack/ssh/config`, и текущая `_ssh_hosts` его игнорирует — на скрине ровно 11 хостов, столько же, сколько `Host`-записей в основном файле;
- защита от циклов Include: лимит глубины (константа, напр. 16) + WARN при превышении;
- нет `~/.ssh/config` — нормальный кейс: пустой вывод, `return 0`, без WARN;
- нечитаемый существующий Include-файл — WARN (edge case обязан оставить след);
- чистый bash (`while read`), без внешних утилит, совместимо с bash и zsh.

**`ak.ssh.host.describe <host>`** — печатает `user@hostname` для меню: `ssh -G <host>` (один вызов, `awk`/`read` по полям `user` и `hostname`). Так автоматически учитываются `Include`, дефолты из `Host *` и наследование — **три бага текущей `_ssh_hosts`**, где `user`/`hostname` объявлены один раз и не сбрасываются на новом `Host`, из-за чего значение протекает из предыдущего блока (`lan-desktop`/`lan-admin` не имеют своего `User`, но показываются как `deploy@…`).
- `ssh -G` доступен с OpenSSH 6.8 (2015) — считаем данностью; если вызов упал, печатать пусто (меню деградирует до голых имён, но работает).

**`ak.ssh.hosts.described()`** — `host<TAB>user@hostname` построчно, для completion. Форкает `ssh -G` на каждый хост (~12 хостов × единицы мс), поэтому кэшируем в файле `${TMPDIR:-/tmp}/ak-ssh-hosts-described.$UID.cache` с инвалидацией по mtime `~/.ssh/config` (+ всех Include). Файл фиксированного имени, перезаписывается — не растёт.

Зарегистрировать `source "${AK_SCRIPT_PATH}/sdk/ssh.sh"` в `index.sh` рядом с `inet.sh`.

### 2. `sdk/shell.sh` — `ak.sh.timeout <seconds> <cmd…>`

Нужна для `status-all` (см. п. 4) и переиспользуема. Реализация: `timeout`/`gtimeout` если есть, иначе fallback — запуск в фоне + watchdog-subshell, убивающий по дедлайну. На Mac оператора `timeout` есть (brew coreutils), на голом macOS — нет, поэтому fallback обязателен. Возврат `124` при срабатывании (соглашение GNU `timeout`), иначе код команды.

### 3. `features/sudo.sh` — машинный вывод статуса

`ak.sudo.status --porcelain` печатает одну стабильную строку вместо человекочитаемой:

```
granted=1 deadline_epoch=1785000000
granted=0
```

Зачем: `status-all` иначе обязан парсить через SSH человекочитаемое «— 23min 14s left», что хрупко и ломается при смене формулировки. Epoch, а не «минут осталось» — тогда абсолютное время считается **в таймзоне оператора**, а не удалённого хоста.

Понадобится `__ak.sudo.timer.deadlineEpoch()`:
- Linux: `systemctl show "${AK_SUDO_UNIT}.timer" -p NextElapseUSecRealtime --value` → epoch;
- macOS: `AKDL` из плиста (уже извлекается в `features/sudo.sh:177`).

Существующую `__ak.sudo.timer.remaining` выразить через неё (DRY) — форматирование остаётся на месте.

**Обратная совместимость**: старая версия на удалённом хосте `--porcelain` не знает и напечатает обычный текст с rc=0. `status-all` обязан это распознать (нет ожидаемого префикса) и показать хост серым с пометкой `ankor-shell outdated`, а не соврать «no grant».

### 4. `features/sudo.sh` — четыре публичные команды

`__ak.sudo.remote.exec <remoteFn> <host> [arg]` — ядро для трёх интерактивных команд:

```bash
ssh -t -o ConnectTimeout="${AK_SUDO_REMOTE_TIMEOUT:-10}" -- "${host}" "bash -lic '${cmd}'"
```

- **Quoting-ловушка закрыта конструктивно**: команда собирается локально в ОДНУ строку-аргумент, поэтому удалённый шелл re-parse'ит ровно то, что задумано, и число никогда не прилетает в `$0`. Guard в `ak.sudo.lend:202` остаётся сетью для ручных вызовов — не трогать.
- **Инъекция невозможна по построению**: `arg` (минуты) валидируется локально до отправки правилом `^[0-9]+$` + диапазон 1..1440, поэтому внутрь одинарных кавычек не попадает ничего экранируемого. Правило вынести в `__ak.sudo.validMinutes()` и переиспользовать в `ak.sudo.lend` (DRY — сейчас заинлайнено в `features/sudo.sh:212`).
- `host` — отдельным элементом argv; `--` защищает от хоста, начинающегося с `-`.
- `-t` обязателен всем трём (пароль читается с tty).
- Диагностика вместо мусора (каждая ветка логируется): `255` → ERR «ssh не смог подключиться к `<host>`»; `127` → ERR «на `<host>` не найдена `ak.sudo.*` — ankor-shell не загружен в интерактивный rc»; иначе пробросить код как есть.
- Хост вне `ak.ssh.hosts` **не блокировать** (может быть `user@ip`).
- Пустой host / лишние аргументы → `ak.sh.err` + usage, `return 1`.

Публичные обёртки — тонкие, каждая с `##`-doc-блоком в каноне репо (`@param`, `@example`): `ak.sudo.remote-lend <host> [minutes]`, `ak.sudo.remote-revoke <host>`, `ak.sudo.remote-status <host>`.

**`ak.sudo.remote-status-all`** — отдельная реализация (не через `exec`: другой режим ssh и параллелизм):

- Хосты берём из `ak.ssh.hosts`. Пусто → информативное сообщение, `return 0`.
- **Никакого tty и никаких промптов**: `ssh -T -n -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new`. `BatchMode` критичен — иначе passphrase-промпт повесит параллельный опрос. `ak.sudo.status` внутри ходит только через `sudo -n`, пароля не просит.
- Удалённая команда: `bash -lic 'command -v ak.sudo.status >/dev/null || exit 127; ak.sudo.status --porcelain'` — явная проверка вместо угадывания по мусору в stderr (`bash -i` без tty пишет «no job control in this shell»). stderr глушим.
- **Параллельность**: каждый хост — фоновый процесс, результат в свой файл во временном каталоге (`mktemp -d`), затем `wait`. Вывод собираем и печатаем в алфавитном порядке — стабильно, независимо от порядка ответов. Ограничение параллелизма не вводим (десятки хостов — норма для ssh), но каждый вызов обёрнут в `ak.sh.timeout ${AK_SUDO_REMOTE_ALL_TIMEOUT:-15}` — `ConnectTimeout` покрывает только фазу коннекта, зависший `bash -lic` после успешного коннекта им не лечится.
- **Cleanup**: `trap` на `EXIT INT TERM` удаляет временный каталог — на всех путях выхода, включая Ctrl-C посреди опроса.
- Классификация результата: `granted=1` → зелёный + `Nm left (until HH:MM)`; `granted=0` → красный `no grant`; rc `127` → серый `ankor-shell not installed`; rc `124` (наш таймаут) или `255` → жёлтый `unreachable`; нераспознанный вывод → серый `ankor-shell outdated`.
- Формат: колонки выровнены по самому длинному имени хоста (`printf` с вычисленной шириной). Цвета — константы `AK_COLOR_*` из `sdk/shell.sh`; при не-tty stdout цвета отключать.
- Код возврата: `0`, даже если часть хостов недоступна (это отчёт, а не проверка). Сводку «N granted / M no grant / K unreachable» печатать в конце.

### 5. `completions/` (новая подсистема)

В репо автодополнения нет вообще — делаем сразу generic, чтобы позже накрыть `ak.git.*` / `ak.docker.*`.

- `completions/zsh/ak.sudo.remote.zsh` — определяет `_ak_sudo_remote` и регистрирует:
  ```zsh
  (( $+functions[compdef] )) && compdef _ak_sudo_remote ak.sudo.remote-lend ak.sudo.remote-revoke ak.sudo.remote-status
  ```
  Именно `compdef`, а НЕ `fpath` + `autoload`: в `~/.zshrc` оператора oh-my-zsh вызывает `compinit` (строка 57) ДО `source index.sh` (строка 145) — дополнять `fpath` уже поздно, а `compdef` доступна. Guard `$+functions[compdef]` спасает конфиги без compinit.
  Кандидаты подавать через `_describe` парами `host:user@hostname` (источник — `ak.ssh.hosts.described`), чтобы fzf-tab и `list-separator` отрисовали меню как у `ssh`. Добавить `zstyle ':completion:*:*:ak.sudo.remote-*:*' list-separator '→'` — у оператора такой zstyle уже стоит для `ssh` (`~/.zshrc:84`), нам нужен свой, он на имя команды.
  `remote-status-all` аргументов не принимает — completion ей не регистрируем.
  Вторую позицию (`15 30 60 120`) предлагать только для `remote-lend` — различать по `$words[1]`.
- `completions/bash/ak.sudo.remote.bash` — `complete -F _ak_sudo_remote_bash …` на те же имена, логика через `COMP_CWORD`, только имена хостов (описаний bash не показывает).
- Загрузчик в `index.sh` (после features): по `ak.sh.isZsh` / `ak.sh.isBash` сорсить нужный каталог. Ошибка загрузки completion не должна ронять source библиотеки.

### 6. Документация

- Doc-блоки в коде по канону 002; `README.md` — если там есть перечень команд.
- Обновить шапку `features/sudo.sh:19-26`: пример «one-shot from another machine» заменить на `ak.sudo.remote-lend`, сырую `ssh`-форму оставить как объяснение guard'а.
- **Follow-up в другом репо (`ankor-dotfiles`, не в этой задаче)**: заменить самописную `_ssh_hosts` в `~/.zshrc:59-83` на вызов `ak.ssh.hosts.described` — тогда у `ssh` и у `ak.sudo.remote-*` один источник данных и разом чинятся протечка `user`, потеря `Include` и хосты с несколькими именами в строке. Завести отдельной задачей после мержа этой.

## Проверка (ручная — тестового каркаса в репо нет, см. backlog 004)

- `bash -n` и `zsh -n` на всех изменённых файлах; `source index.sh` в bash и в zsh без ошибок.
- `ak.ssh.hosts` — 11 хостов основного конфига **плюс** хосты из `~/.orbstack/ssh/config`, БЕЗ `*` и `198.51.100.* lan-*`.
- `ak.ssh.host.describe lan-desktop` — user берётся из эффективного конфига, а не протекает из соседнего блока.
- `ak.sudo.remote-lend <TAB>` — меню как у `ssh` (alias → user@host); второй `<TAB>` — минуты.
- Реальный прогон на `vps-india`: `remote-lend 5` → `remote-status` → `remote-status-all` (этот хост зелёный, остальные красные) → `remote-revoke` → `remote-status-all` (все красные).
- `remote-status-all` с заведомо мёртвым хостом в конфиге — жёлтый, укладывается в таймаут, общее время ≈ времени самого медленного хоста (доказательство параллельности), Ctrl-C посреди опроса не оставляет временного каталога.
- Негатив: несуществующий хост (255), `remote-lend host 0` и `host 9999` — локальная ошибка валидации без сетевого вызова.

## Связи

- `features/sudo.sh`; `index.sh:38` (TODO `ak.ssh.*`); backlog 004 (тесты), 002 (канон doc-комментариев).
