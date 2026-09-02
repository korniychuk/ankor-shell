---
id: 00d
type: task
status: done
created: 2026-09-03
completed: 2026-09-03
---

# 00d — `ak.inet.ping.*`: выход по `q`, не только Ctrl+C

## Повод

`ic` (`ak.inet.check; echo; ak.inet.ping.DNS`) теперь запускается из Herdr-лаунчера
(`ankor-dotfiles/herdr/apps/ic.sh`, dotfiles task 030) в отдельной вкладке,
которая закрывается вместе с командой. Бесконечный `ping` останавливался только
Ctrl+C, а после него wrapper держал вкладку «press any key» — лишний шаг.

## Решение

`__ak.inet.ping.interactive <target>` в `sdk/inet.sh`: `ping` уходит в фон,
цикл читает по одной клавише с таймаутом 0.2 с (`read -k1` в zsh, `read -n1` в
bash); `q`/`Q` или Ctrl+C (trap INT) убивают ping и возвращают управление.
Без tty на stdin — обычный foreground `ping` (скрипты/пайпы не ломаются).
`ak.inet.ping.IPv4` / `ak.inet.ping.DNS` делегируют ему. Wrapper в dotfiles
больше не ждёт клавишу после ping.

## Проверка

- bash 5: `printf q | …` не tty → foreground ping (fallback); с tty — `q` завершает.
- zsh: то же через `read -k1`.
