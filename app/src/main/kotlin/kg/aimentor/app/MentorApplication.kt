package kg.aimentor.app

import android.app.Application
import android.content.Context

// Ручное внедрение зависимостей: всё создаётся в одном месте, ViewModel получают готовые объекты
class AppContainer(context: Context) {
    val session: Session = PrefsSession(context)
    val cache: Cache = PrefsCache(context)
    val api = MentorApi(BuildConfig.BASE_URL) { session.token }
    val reminders: ReminderScheduler = WorkReminderScheduler(context)
}

class MentorApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        WorkReminderScheduler.createChannel(this)
    }
}
