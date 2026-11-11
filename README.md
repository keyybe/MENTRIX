# Mento – ИИ-ментор: MVP

iOS-приложение (Swift + SwiftUI, см. [`ios/README.md`](ios/README.md)) и сервер (Swift + Vapor + PostgreSQL), которые ведут человека по личному плану обучения в IT: миссия на каждый день, проверка ответов ИИ, повторение слабых тем.

## Что умеет

| Функция | Где в коде |
|---|---|
| Вход через Google, вход и регистрация по email/паролю (PBKDF2) и JWT-сессии | `ios/Mento/UI/LoginView.swift`, `server/Sources/MentorServer/Accounts.swift`, `POST /api/auth/*` |
| F1 Онбординг и выбор направления, смена направления | `OnboardingView.swift`, `POST /api/profile` |
| F2 План на 8 недель из проверенных источников (42 задания на направление, есть задания с кодом) | `MentorService.swift` (Planner), `Resources/sources.json` |
| F3 Экран «Сегодня» и миссия дня, сгенерированная ИИ без повторов | `HomeView.swift`, `GET /api/today` |
| F4 Проверка ответов (текст и код) | `Llm.swift`, `POST /api/answer` |
| F5 Чат «Застрял»: подсказки без готового ответа | `ChatView.swift`, `POST /api/chat` |
| F6 Серия занятий и ежедневные напоминания | `MentorService.bumpStreak`, `ios/Mento/Core/Reminders.swift` |
| F7 Перестройка плана: интервальные повторения (1 → 3 → 7 дней) и пересборка после паузы | `MentorService.scheduleReview` |
| F8 Профиль, настройки (цель, минуты, дни), прогресс, удаление аккаунта | `ProfileView.swift`, `PUT /api/settings`, `DELETE /api/account` |
| Офлайн-режим: последние данные сохраняются на устройстве | `ios/Mento/Core/Storage.swift` |
| Хранение в PostgreSQL (или в памяти для разработки) | `Store.swift` |
| Статистика активности для команды | `GET /admin/stats` |

## Быстрый старт (локально)

Нужен Xcode.

```bash
cd server
AUTH_DEV=true swift run mentor-server   # сервер на http://localhost:8080 (проверка: /health)
```

`AUTH_DEV=true` разрешает вход без аккаунта, без `DATABASE_URL` данные хранятся в памяти.
Затем открой `ios/Mento.xcodeproj`, выбери схему **Mento** и симулятор, нажми Run.
Debug-сборка ходит на `http://localhost:8080/`.

### С локальной PostgreSQL (данные не пропадают при перезапуске)

```bash
brew install postgresql@14 && brew services start postgresql@14
psql -d postgres -c "CREATE ROLE mentor LOGIN PASSWORD 'пароль';" -c "CREATE DATABASE mentor OWNER mentor;"
```

В `.env` (см. `.env.example`) укажи `DATABASE_URL`, `DATABASE_USER`, `DATABASE_PASSWORD`, затем:

```bash
set -a; . ./.env; set +a
cd server && swift run mentor-server     # в логе: «Хранилище: PostgreSQL»
```

Таблицы создаются сами при первом запуске.

## Тесты

```bash
cd server && swift test                       # без базы: тесты PostgreSQL пропускаются
TEST_DATABASE_URL=postgres://mentor:пароль@localhost:5432/mentor_test swift test   # вместе с PostgreSQL
```

Тесты iOS: схема **Mento** в Xcode, ⌘U.
Тесты сервера, iOS и сборку Docker-образа на каждый push запускает GitHub Actions (`.github/workflows/ci.yml`).

## Переменные окружения сервера

| Переменная | Зачем | По умолчанию |
|---|---|---|
| `DATABASE_URL` | PostgreSQL: `postgres://user:pass@host:5432/db` | нет – данные в памяти |
| `DATABASE_USER`, `DATABASE_PASSWORD` | если не указаны в адресе | – |
| `JWT_SECRET` | секрет для подписи токенов (`openssl rand -base64 32`) | временный, после перезапуска всем придётся войти заново |
| `GOOGLE_CLIENT_ID` | Client ID из Google Cloud (через запятую, если несколько) | нет – вход через Google выключен |
| `AUTH_DEV` | `true` – вход без аккаунта. **Не включай на боевом сервере** | `false` |
| `ADMIN_TOKEN` | доступ к `GET /admin/stats` (заголовок `X-Admin-Token`) | нет – статистика выключена |
| `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL` | внешняя модель с OpenAI-совместимым API | без ключа и модели – офлайн-проверка |
| `PORT` | порт | 8080 |

Ключи и пароли храни только в переменных окружения или в `.env` (он в `.gitignore`), никогда в коде.

### Внешняя модель ИИ

Протокол `LlmClient` скрывает, кто проверяет ответы и пишет подсказки:
- `RuleBasedLlm` – офлайн-проверка по ключевым понятиям задания;
- `HttpLlm` – внешняя модель (Gemini, OpenAI и др.);
- `FallbackLlm` – пробует внешнюю модель, а при ошибке отвечает офлайн-проверкой.

Gemini бесплатно: ключ на [aistudio.google.com](https://aistudio.google.com/), `LLM_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai/`, `LLM_MODEL=<актуальная Flash-модель из списка в AI Studio>`.

## Вход через Google

Настройка описана в [`ios/README.md`](ios/README.md#вход-через-google). Серверу нужен `GOOGLE_CLIENT_ID` с iOS Client ID.

## Деплой сервера

```bash
cp .env.example .env          # заполни JWT_SECRET, DB_PASSWORD и остальное
docker compose up --build     # сервер + PostgreSQL на http://localhost:8080
```

На хостинге (Railway, Render, Fly.io, VPS) достаточно `Dockerfile` и переменных окружения из таблицы.
Сервер рассчитан на **один экземпляр**: очередь запросов одного пользователя держится в памяти процесса.

## Статистика

```bash
curl -H "X-Admin-Token: $ADMIN_TOKEN" https://твой-сервер/admin/stats
```

## Контент

`server/Sources/MentorServer/Resources/sources.json` – проверенные источники и задания (`"code": true` – задание с кодом).
Проверка ссылок: `cd server && swift run check-links`.
