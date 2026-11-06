# ИИ-ментор для iOS (Swift + SwiftUI)

iOS-версия Android-приложения из `app/`: те же экраны и функции, тот же сервер (`server/`).
Без сторонних зависимостей, iOS 17+.

## Запуск

1. Запусти сервер из корня репозитория: `./gradlew :server:run` (проверка: http://localhost:8080/health).
2. Открой `ios/Mentrix.xcodeproj` в Xcode, выбери схему **Mentrix** и симулятор, нажми Run.
   Debug-сборка ходит на `http://localhost:8080/`, а симулятор видит localhost компьютера.
3. Нажми «Без аккаунта (для разработки)» или зарегистрируйся по email.

Тесты: `⌘U` в Xcode или
```bash
xcodebuild -project ios/Mentrix.xcodeproj -scheme Mentrix -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
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

| Android (`app/`) | iOS (`ios/Mentrix/`) |
|---|---|
| `MentorApi.kt` (Ktor) | `Core/MentorAPI.swift` (URLSession) |
| `shared/Models.kt` | `Core/Models.swift` |
| `MentorViewModel.kt` | `Core/MentorViewModel.swift` (`@Observable`) |
| `Storage.kt` (SharedPreferences) | `Core/Storage.swift` (токен в Связке ключей, остальное в UserDefaults) |
| `Reminders.kt` (WorkManager) | `Core/Reminders.swift` (локальные уведомления на неделю вперёд) |
| `GoogleSignIn.kt` (Credential Manager) | `Core/GoogleSignIn.swift` |
| `Avatar.kt` | `Core/AvatarStore.swift` + `UserAvatar` в `UI/Theme.swift` |
| `Theme.kt` | `UI/Theme.swift` |
| `LoginScreen.kt`, `Screens.kt`, `HomeScreen.kt`, `LessonScreen.kt`, `ChatScreen.kt`, `ProfileScreen.kt` | `UI/*View.swift` |
| `MentorApp.kt` | `App/RootView.swift` |
| `MentorViewModelTest.kt` | `MentrixTests/MentorViewModelTests.swift` |

Отличия от Android:
- Шрифт – системный SF Rounded вместо Manrope из Google Fonts.
- Напоминания: iOS не умеет пропускать один день у повторяющегося уведомления, поэтому приложение
  ставит уведомления на 7 дней вперёд и обновляет их при открытии и после засчитанного урока.
- Нет иконки приложения: добавь картинку 1024×1024 в `Assets.xcassets/AppIcon`.
