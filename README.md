# ИИ-ментор

Android-приложение (Kotlin + Jetpack Compose) и сервер (Kotlin + Ktor + PostgreSQL), которые ведут человека по личному плану обучения в IT: миссия на каждый день, проверка ответов ИИ, повторение слабых тем.

## Что умеет

| Функция | Где в коде |
|---|---|
| Вход через Google (Credential Manager) и JWT-сессии | `app/GoogleSignIn.kt`, `server/Auth.kt`, `POST /api/auth/google` |
| F1 Онбординг и выбор направления, смена направления | `app/Screens.kt` (OnboardingScreen), `POST /api/profile` |
| F2 План на 8 недель из проверенных источников (42 задания на направление, есть задания с кодом) | `server/MentorService.kt` (Planner), `server/resources/sources.json` |
| F3 Экран «Сегодня» и миссия дня, сгенерированная ИИ без повторов | `TodayScreen`, `GET /api/today` |
| F4 Проверка ответов (текст и код) | `server/Llm.kt`, `POST /api/answer` |
| F5 Чат «Застрял»: подсказки без готового ответа | `app/ChatScreen.kt`, `POST /api/chat` |
| F6 Серия занятий и ежедневные напоминания | `MentorService.bumpStreak`, `app/Reminders.kt` (WorkManager) |
| F7 Перестройка плана: интервальные повторения (1 → 3 → 7 дней) и пересборка после паузы | `MentorService.scheduleReview` |
| F8 Профиль, настройки (цель, минуты, дни), прогресс, удаление аккаунта | `ProfileScreen`, `PUT /api/settings`, `DELETE /api/account` |
| Офлайн-режим: последние данные сохраняются на устройстве | `app/Storage.kt` |
| Хранение в PostgreSQL (или в памяти для разработки) | `server/Store.kt` |
| Статистика активности для команды | `GET /admin/stats` |

## Быстрый старт (локально)

Нужен JDK 17+ и Android Studio.

```bash
./gradlew :server:test                 # тесты сервера
./gradlew :app:testDebugUnitTest       # тесты приложения
./gradlew :server:run                  # сервер на http://localhost:8080 (проверка: /health)
```

`./gradlew :server:run` запускает сервер в режиме разработки: данные в памяти, вход без Google разрешён (`AUTH_DEV=true`).
Запусти модуль `app` на эмуляторе и нажми «Войти без Google (для разработки)». Debug-сборка ходит на `http://10.0.2.2:8080/`.

## Переменные окружения сервера

| Переменная | Зачем | По умолчанию |
|---|---|---|
| `DATABASE_URL` | PostgreSQL: `jdbc:postgresql://host:5432/db` или `postgres://user:pass@host:5432/db` | нет – данные в памяти |
| `DATABASE_USER`, `DATABASE_PASSWORD` | если не указаны в адресе | – |
| `JWT_SECRET` | секрет для подписи токенов (`openssl rand -base64 32`) | временный, после перезапуска всем придётся войти заново |
| `GOOGLE_CLIENT_ID` | Web Client ID (через запятую, если несколько) | нет – вход через Google выключен |
| `AUTH_DEV` | `true` – вход без Google. **Не включай на боевом сервере** | `false` (у `:server:run` – `true`) |
| `ADMIN_TOKEN` | доступ к `GET /admin/stats` (заголовок `X-Admin-Token`) | нет – статистика выключена |
| `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL` | внешняя модель с OpenAI-совместимым API | без ключа и модели – офлайн-проверка |
| `PORT` | порт | 8080 |

Ключи и пароли храни только в переменных окружения или в `.env` (он в `.gitignore`), никогда в коде.

### Внешняя модель ИИ

Интерфейс `LlmClient` скрывает, кто проверяет ответы и пишет подсказки:
- `RuleBasedLlm` – офлайн-проверка по ключевым понятиям задания;
- `HttpLlm` – внешняя модель (Gemini, OpenAI и др.);
- `FallbackLlm` – пробует внешнюю модель, а при ошибке отвечает офлайн-проверкой и пишет в лог `WARN FallbackLlm`.

Gemini бесплатно: ключ на [aistudio.google.com](https://aistudio.google.com/), `LLM_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai/`, `LLM_MODEL=<актуальная Flash-модель из списка в AI Studio>`.

Защита расходов: не больше 40 запросов к модели на человека в день (`LLM_DAILY_LIMIT`), дальше – офлайн-режим. Ответ ученика передаётся модели как данные, инструкции внутри него игнорируются, а ответ короче 3 слов не засчитывается.

## Вход через Google: настройка

1. [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → Credentials.
2. Создай **OAuth client ID** типа **Web application** – его ID нужен и приложению, и серверу.
3. Создай **OAuth client ID** типа **Android**: пакет `kg.aimentor.app` и SHA-1 ключа подписи (`./gradlew :app:signingReport`). Отдельно для debug и release.
4. Приложению – в `~/.gradle/gradle.properties`:
   ```
   aimentor.googleClientId=<Web Client ID>
   aimentor.serverUrl=https://твой-сервер/
   ```
5. Серверу – `GOOGLE_CLIENT_ID=<Web Client ID>`.

## Деплой сервера

Docker-образ собирает только сервер, Android SDK не нужен:

```bash
cp .env.example .env          # заполни JWT_SECRET, DB_PASSWORD и остальное
docker compose up --build     # сервер + PostgreSQL на http://localhost:8080
```

На хостинге (Railway, Render, Fly.io, VPS) достаточно `Dockerfile` и переменных окружения из таблицы. Таблицы в базе создаются при запуске.
Сервер рассчитан на **один экземпляр**: очередь запросов одного пользователя держится в памяти процесса.

## Статистика

```bash
curl -H "X-Admin-Token: $ADMIN_TOKEN" https://твой-сервер/admin/stats
```
Ответ: всего пользователей, активных за 1/7/30 дней, новых профилей, ответов и зачётов за неделю, обращений в чат.
Хранятся только тип события и день. После удаления аккаунта события человека тоже удаляются.

## Контент

`server/src/main/resources/sources.json` – проверенные источники и задания (`"code": true` – задание с кодом).
Перед релизом и время от времени проверяй ссылки: `./gradlew :server:checkLinks`.
Тест `sourcesAreValid` следит, чтобы в каждом направлении хватало заданий на 8 недель и были задания с кодом.

## Что дальше

1. Подключить хостинг и Google Cloud (см. выше) и выпустить закрытую бету.
2. Расширить контент для уровня «Знаю основы»: сейчас продолжающим доступна только продвинутая половина базы (21 задание).
3. Потоковые ответы в чате и вынос строк в `strings.xml` (локализация).
4. При росте нагрузки – несколько экземпляров сервера (блокировки в БД вместо памяти) и аналитика в приложении (Firebase).
