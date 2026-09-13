---
id: 00e
type: task
status: planned
created: 2026-09-14
---

# 00e — `ak.inet.check`: параллельная послойная диагностика сети

## Повод

`ic` (alias в `config.sh:78`, а также Herdr-вкладка `ankor-dotfiles/herdr/apps/ic.sh`)
= `ak.inet.check; echo; ak.inet.ping.DNS`. Текущие три проверки слабые и дают
ложные результаты:

- `__ak.inet.check.IPv4` — один `ping 8.8.8.8`: там, где режут ICMP (отели,
  коворкинги), `[Fail]` при живом интернете;
- `__ak.inet.check.DNS` — `ping google.com`: смешивает DNS и ICMP, без таймаута
  на резолв (в коде `TODO: add timeout`);
- `__ak.inet.check.connectivity` — `curl -I http://google.com`: captive portal
  может выглядеть как успех.

Нужно: быстро (≈2–3 с) и **параллельно** показать статус каждого слоя сети и
одной строкой сказать, где именно обрыв. Этап 2 (бесконечный ping) не меняется.

## Решения (согласованы с оператором)

1. **Переписываем `ak.inet.check` на месте**, новой функции не заводим. Вызовов
   всего два (`config.sh:78` alias `ic`, `ankor-dotfiles/herdr/apps/ic.sh`), оба
   используют только вывод. Старые `__ak.inet.check.IPv4/DNS/connectivity`
   удаляются (других вызовов нет — проверено grep по ankor-shell,
   ankor-shell_custom-scripts, ankor-dotfiles).
2. **Этап 2 не трогаем**: `ak.inet.ping.*` / `__ak.inet.ping.interactive` (00d и
   фикс `efa2b4e` — возврат собственного статуса ping) остаются как есть; цель
   бесконечного ping — по-прежнему `google.com`.
3. **Каждая проверка — отдельная приватная функция** `__ak.inet.check.<name>`,
   все запускаются одновременно в фоне, каждая пишет результат в свой файл во
   временной папке; после общего `wait` результаты печатаются в **фиксированном
   порядке** (не в порядке завершения). Временная папка (`mktemp -d`) удаляется
   на любом выходе, включая Ctrl+C.
4. **Каждая проверка ограничена по времени** (1–2 с). Весь этап 1 ≤ ~3 с даже при
   полностью лежащей сети. macOS не имеет `timeout` из коробки — нужен
   переносимый хелпер (фон + `sleep` + `kill`), если у инструмента нет своего
   флага таймаута.
5. **Библиотека грузится и в bash 5, и в zsh** (`index.sh` источается из обоих;
   `__ak.inet.ping.interactive` уже различает их). Код обязан работать в обоих.
   Фоновые задачи **не должны печатать job-control шум** (`[2] 38492`,
   `+ 38492 done`) в интерактивном zsh/bash — например, весь параллельный блок
   выполняется в subshell `( … )`, где job control выключен.
6. **Платформы**: основная — macOS; на Linux (серверы) функция не должна падать.
   Проверка, для которой нет инструмента или данных, печатает `[Skip]` с
   причиной или опускается (см. таблицу), но никогда не валит весь вывод.
7. **DoH запускается только если хотя бы одна DNS-проверка упала** — после
   основного `wait`, чтобы не гоняться вхолостую.
8. **Tailscale-проверка — только если Tailscale установлен** (бинарь найден);
   иначе строка не выводится вовсе. Без `jq` — тоже не выводится.

## Проверки (этап 1)

Порядок вывода = порядок строк таблицы.

| # | Строка | Как | OK / Fail / опустить |
|---|---|---|---|
| 1 | `Link` | интерфейс primary default route **физической** сети + его IPv4 | Fail: нет интерфейса/адреса или адрес `169.254.*` (нет DHCP). Показать `en0 192.168.1.23` |
| 2 | `Router` | `ping -c1` шлюза физического интерфейса | Показать IP и RTT. Fail: нет ответа |
| 3 | `ISP hop` | найти 2-й хоп: `traceroute -n -m 2 -q 1 -w 1 1.1.1.1` (на этой машине ≈0,08 с, хоп 2 = `100.64.0.1`, CGNAT провайдера), затем `ping -c1` его | **Опустить строку**, если хоп не найден (`*`, нет `traceroute`) или primary default route идёт через туннель (`utun*` / `tun*` / `wg*`) — тогда хоп 2 внутри VPN и ничего не значит |
| 4 | `Ping 1.1.1.1` | `ping -c1`, RTT | |
| 5 | `Ping 8.8.8.8` | `ping -c1`, RTT | |
| 6 | `TCP 1.1.1.1:443` | TCP connect с таймаутом (`nc -z -G 1` на macOS / `-w 1` на Linux, или `curl --connect-timeout`) | |
| 7 | `TCP 8.8.8.8:443` | то же | |
| 8 | `IPv6` | `ping6 -c1 2001:4860:4860::8888` (Linux: `ping -6`) | **Информационная**: не влияет на код возврата и вердикт (у многих провайдеров IPv6 нет) |
| 9 | `DNS system` | резолв `google.com` **системным** resolver'ом, с таймаутом. На macOS именно системный путь (`dscacheutil -q host -a name …` под таймаутом), а не `dig` без `@` — тот читает `/etc/resolv.conf` и не видит split-DNS Tailscale/VPN из `scutil --dns`. Linux: `getent hosts` | |
| 10 | `DNS @1.1.1.1` | `dig @1.1.1.1 +time=1 +tries=1 +short google.com A` — OK, если есть A-запись | Нет `dig` → `[Skip]` |
| 11 | `DNS @8.8.8.8` | то же для `8.8.8.8` | то же |
| 12 | `DNS over HTTPS` | **только если упала хотя бы одна из 9–11**: `curl -s --max-time 2 -H 'accept: application/dns-json' 'https://1.1.1.1/dns-query?name=google.com&type=A'`, OK при `"Status":0` и непустом `Answer` | Иначе строки нет |
| 13 | `Default route` | `[Info]`: интерфейс primary default route; если это туннель — пометить `VPN tunnel` | macOS: `route -n get default` (**не** `netstat -rn`: там всегда есть scoped `default … utun7` с флагом `I` от Tailscale, он не primary). Linux: `ip route show default` |
| 14 | `Proxy` | `[Info]`: включён ли системный HTTP/HTTPS/SOCKS прокси (`scutil --proxy`) | Только macOS, иначе строки нет |
| 15 | `Tailscale` | `[Info]`: exit node включён/нет и его имя (`tailscale status --json` → `.ExitNodeStatus`, daemon по умолчанию) | Только если найден бинарь `tailscale` (PATH или `/usr/local/bin/tailscale`) и есть `jq` |

Физический шлюз (строки 1–2): берётся из primary default route, если тот не
туннель; иначе — из default route физического интерфейса (macOS: `en*`, флаг `G`,
не scoped `I`; Linux: `ip route` без `dev tun*/wg*/tailscale*`).

### Формат вывода (ориентир)

```
Internet connection checking ...
[OK]   Link            en0 192.168.1.23
[OK]   Router          192.168.1.1     13 ms
[OK]   ISP hop         100.64.0.1      19 ms
[OK]   Ping 1.1.1.1                    21 ms
[Fail] Ping 8.8.8.8
[OK]   TCP 1.1.1.1:443
[OK]   TCP 8.8.8.8:443
[Fail] IPv6            (info)
[OK]   DNS system
[OK]   DNS @1.1.1.1
[OK]   DNS @8.8.8.8
[Info] Default route   en0
[Info] Proxy           none
[Info] Tailscale       exit node: none
=> Internet OK (ICMP to 8.8.8.8 filtered)
```

Цвета — через существующие хелперы `sdk/shell.sh`, если они там есть для этого;
иначе без цвета. Заголовок `Internet connection checking ...` оставить.

## Вердикт (последняя строка) и код возврата

`public_ip_ok` = хотя бы одна из 4–7 OK. `dns_ok` = `DNS system` OK.
Правила по порядку, первое совпавшее:

1. Link Fail → `No network link (Wi-Fi off / no DHCP lease)`.
2. `public_ip_ok`:
   - `DNS system` Fail, но `@1.1.1.1` или `@8.8.8.8` OK → `Local DNS resolver broken (router / VPN / Tailscale DNS)`;
   - все 9–11 Fail, DoH OK → `Plain DNS (UDP/53) blocked, DNS over HTTPS works`;
   - все 9–11 и DoH Fail → `DNS unreachable`;
   - оба ping Fail, TCP OK → `Internet OK (ICMP filtered)`;
   - иначе `Internet OK` (частичные фейлы — в скобках).
3. Не `public_ip_ok`:
   - Router Fail → `Router unreachable — Wi-Fi / LAN problem (or router ignores ping)`;
   - Router OK, ISP hop Fail → `Router up, ISP uplink down`;
   - Router OK, ISP hop OK → `ISP reachable, internet beyond it down`;
   - Router OK, ISP hop опущен → `Router up, internet down (ISP or beyond)`.
   - Если primary default route — туннель, дописать `; traffic goes through VPN tunnel <if>`.

Код возврата: `0`, если `public_ip_ok && dns_ok`; иначе `1`. IPv6 и `[Info]`
не влияют.

## Границы (ownership)

- Меняется: `sdk/inet.sh` (только `ak.inet.check` и `__ak.inet.check.*`, плюс
  новые приватные хелперы там же), новый тест `tests/inet-check.test.sh`.
- Не меняется: `ak.inet.ping.*`, `__ak.inet.ping.interactive`, `config.sh`,
  всё в `ankor-dotfiles`.
- Никакой сети в тестах: sandbox исполнителя сети не имеет.

## Тесты

В репо нет тест-фреймворка (`docs/backlog/004-smoke-tests.md`) — добавить
самодостаточный `tests/inet-check.test.sh` (bash 5):

- каталог-заглушка в начале `PATH` с фейковыми `ping`, `ping6`, `traceroute`,
  `nc`, `dig`, `curl`, `route`, `scutil`, `dscacheutil`, `tailscale`, `jq`
  (или реальный `jq`), поведение задаётся env-переменной сценария;
- сценарии: всё OK; ICMP режут (ping Fail, TCP OK); DNS system Fail + dig OK;
  все dig Fail + DoH OK (и проверка, что DoH **не** вызывается в сценарии «всё
  OK»); сеть лежит за роутером (Router OK, остальное Fail); нет link; primary
  default route через `utun` (ISP hop опущен, пометка туннеля); Tailscale не
  установлен (строки нет);
- проверять строки статусов, порядок строк, вердикт и код возврата;
- **параллельность**: фейки спят по 1 с, весь этап 1 обязан уложиться в < 3 с;
- прогон и под `bash`, и под `zsh -f` (источать `sdk/inet.sh` и нужные
  зависимости); отсутствие job-control шума в выводе (`zsh -fic`);
- после Ctrl+C / обычного выхода временная папка удалена.

Гейты, которые должны пройти:

```bash
bash tests/inet-check.test.sh
shellcheck -s bash sdk/inet.sh tests/inet-check.test.sh   # без новых предупреждений в затронутых функциях
```

## Живая проверка (оператор, после интеграции — не исполнитель)

На этом Mac в Herdr `prefix+m → i`: обычная сеть; выключенный Wi-Fi; сломанный
DNS (`networksetup -setdnsservers Wi-Fi 192.0.2.1`, потом `empty`); включённый
exit node. Сверить вердикты и что этап 1 занимает ≈2–3 с.
