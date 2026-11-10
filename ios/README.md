# Mento – ИИ-ментор для iOS (Swift + SwiftUI)

iOS-приложение ИИ-ментора. Работает с сервером из `server/` (Swift + Vapor).
Без сторонних зависимостей, iOS 17+.

## Запуск

1. Запусти сервер из корня репозитория: `cd server && AUTH_DEV=true swift run mentor-server` (проверка: http://localhost:8080/health).
2. Открой `ios/Mento.xcodeproj` в Xcode, выбери схему **Mento** и симулятор, нажми Run.
   Debug-сборка ходит на `http://localhost:8080/`, а симулятор видит localhost компьютера.
3. Нажми «Без аккаунта (для разработки)» или зарегистрируйся по email.

Тесты: `⌘U` в Xcode или
```bash
xcodebuild -project ios/Mento.xcodeproj -scheme Mento -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

## Настройки

Значения задаются в `ios/Config.xcconfig`. Свои лучше писать в `ios/Config.local.xcconfig`, он в `.gitignore`:

```
MENTOR_SERVER_URL_RELEASE = https:/$()/твой-сервер/
GOOGLE_IOS_CLIENT_ID = 1234567890-xxxx.apps.googleusercontent.com
DEVELOPMENT_TEAM = ABCDE12345
```

### Вход через Google

1. Google Cloud Console → Credentials → **OAuth client ID** типа **iOS**, Bundle ID `kg.aimentor.app`.
2. Его ID впиши в `GOOGLE_IOS_CLIENT_ID`.
3. Добавь этот же ID на сервер через запятую: `GOOGLE_CLIENT_ID=<Web Client ID>,<iOS Client ID>`.
   У ID-токена, который получает iOS-приложение, audience – iOS-клиент.

Вход сделан без Google SDK: OAuth 2.0 + PKCE в системном окне `ASWebAuthenticationSession`.

## Что где

| Файл | Что делает |
|---|---|
| `Core/MentorAPI.swift` | запросы к серверу (URLSession) |
| `Core/Models.swift` | модели данных API |
| `Core/MentorViewModel.swift` | состояние приложения (`@Observable`) |
| `Core/Storage.swift` | токен в Связке ключей, остальное в UserDefaults |
| `Core/Reminders.swift` | локальные уведомления на неделю вперёд |
| `Core/GoogleSignIn.swift` | вход через Google |
| `Core/AvatarStore.swift` | фото профиля |
| `UI/Theme.swift` | цвета, шрифты, общие компоненты |
| `UI/*View.swift` | экраны |
| `App/RootView.swift` | навигация между экранами |
| `MentoTests/MentorViewModelTests.swift` | тесты (Swift Testing) |

Заметки:
- Шрифт – системный SF Rounded.
- Напоминания: iOS не умеет пропускать один день у повторяющегося уведомления, поэтому приложение
  ставит уведомления на 7 дней вперёд и обновляет их при открытии и после засчитанного урока.
- Нет иконки приложения: добавь картинку 1024×1024 в `Assets.xcassets/AppIcon`.
