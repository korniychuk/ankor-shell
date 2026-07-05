---
id: 006
type: backlog
status: backlog
created: 2026-07-05
---

# 006 — Модуль ak.assert.*: валидация и assertions

## Задача
Завести полноценный assert/validation модуль `sdk/assert.sh` (`ak.assert.*`) по образцу лучшего, что есть в reference-библиотеке. Закрывает целый пласт TODO: «arg-checking helpers» (`index.sh`), «Check docker installed» (`sdk/docker.sh:44,64`), «normalize boolean» (3 места), ручные `echo 'ArgError...' >&2` по всем модулям.

## Желаемый результат
- `ak.assert [[ ... ]] [errorCode] [errorText]` — ядро: условие передаётся как argv (не строка), токены ре-квотируются через `${var@Q}` перед eval.
- Типизированные обёртки: `ak.assert.eq/ne/gt/lt/ge/le` (числа), `ak.assert.strEq/strNe` — с цветной диагностикой Expected/Actual/Diff и Location через `${BASH_SOURCE[1]}:${BASH_LINENO[0]}`.
- `ak.assert.envVar name [code] [text]` (+ `.ge`), `ak.assert.cmdExist cmd` — интеграция с `ak.sh.param.required` (оставить как алиас или deprecated).
- `ak.sh.toBool` / нормализация falsy-значений (`true/1/yes/y` → канон) — закрывает 3 TODO.
- Все падения — через `ak.sh.die` (005) с per-domain exit-кодами по схеме из 002.
- Doc-комментарии в каноне 002; unit-тесты (004).

## Контекст / зацепки
- Разбор argv-движка образца (парсинг хвостовых optional-аргументов, envsubst-темплейтинг, `_skipCondition`): `ankor/hardening-ref-notes.md`.
- Assert-модуль двойного назначения: он же — test-framework для spec-раннера (004).

## Открытые вопросы
- Домен: `ak.assert.*` (новый) vs `ak.sh.assert.*`? Предлагается новый — модуль самостоятельный.
- Поведение в интерактивном shell: assert, как и die, не должен убивать сессию (return-семантика из 005).
