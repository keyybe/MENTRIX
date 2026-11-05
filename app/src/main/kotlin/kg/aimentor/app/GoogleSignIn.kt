package kg.aimentor.app

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential

sealed interface GoogleSignInResult {
    data class Success(val idToken: String) : GoogleSignInResult
    data object Cancelled : GoogleSignInResult
    data class Failed(val message: String) : GoogleSignInResult
}

// Показывает системное окно «Войти через Google» и возвращает ID-токен для сервера.
// context должен быть Activity: окну входа нужен экран, поверх которого его показать.
suspend fun signInWithGoogle(context: Context, webClientId: String): GoogleSignInResult {
    val request = GetCredentialRequest.Builder()
        .addCredentialOption(GetSignInWithGoogleOption.Builder(webClientId).build())
        .build()
    return try {
        val credential = CredentialManager.create(context).getCredential(context, request).credential
        if (credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            GoogleSignInResult.Success(GoogleIdTokenCredential.createFrom(credential.data).idToken)
        } else {
            GoogleSignInResult.Failed("Неожиданный тип учётных данных")
        }
    } catch (e: GetCredentialCancellationException) {
        GoogleSignInResult.Cancelled
    } catch (e: GetCredentialException) {
        GoogleSignInResult.Failed("Не удалось войти через Google")
    }
}
