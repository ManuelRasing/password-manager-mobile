package com.personal.password_manager.autofill

import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import com.personal.password_manager.R

/**
 * Invoked when the user taps the "Unlock Password Manager" autofill suggestion.
 * Biometric-unlocks, reads the shared vault, decrypts the cached credentials,
 * and returns the chosen one as an autofill [Dataset].
 *
 * Requires biometric unlock to be enabled in the app — that's the only place
 * the vault key is stored at rest (Flutter's in-memory key is unreachable from
 * this separate process).
 */
@RequiresApi(Build.VERSION_CODES.O)
class AutofillAuthActivity : AppCompatActivity() {

    private var usernameId: AutofillId? = null
    private var passwordId: AutofillId? = null
    private var webDomain: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        usernameId = intentExtra(PasswordManagerAutofillService.EXTRA_USERNAME_ID)
        passwordId = intentExtra(PasswordManagerAutofillService.EXTRA_PASSWORD_ID)
        webDomain = intent.getStringExtra(PasswordManagerAutofillService.EXTRA_WEB_DOMAIN)

        promptBiometric()
    }

    private fun promptBiometric() {
        val executor = ContextCompat.getMainExecutor(this)
        val prompt = BiometricPrompt(this, executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    onUnlocked()
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    cancel()
                }
            })

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Unlock to autofill")
            .setSubtitle("Authenticate to fill your saved password")
            .setNegativeButtonText("Cancel")
            .build()

        prompt.authenticate(info)
    }

    private fun onUnlocked() {
        val vaultKey = VaultReader.readVaultKey(this)
        if (vaultKey == null) {
            toastAndCancel(
                "Open the app and enable Biometric Unlock in Settings to use autofill.",
            )
            return
        }

        val cached = VaultReader.readCachedCredentials(this)
        if (cached.isEmpty()) {
            toastAndCancel("No credentials cached yet. Open the app once, then try again.")
            return
        }

        // Prefer credentials whose URL matches the requesting domain; fall back to all.
        val matches = cached.filter { DomainMatcher.matches(it.url, webDomain) }
        val list = matches.ifEmpty { cached }

        showPicker(list, vaultKey)
    }

    private fun showPicker(list: List<CachedCredential>, vaultKey: ByteArray) {
        val labels = list.map { c ->
            if (c.usernameHint.isNotBlank()) "${c.siteName} — ${c.usernameHint}" else c.siteName
        }.toTypedArray()

        AlertDialog.Builder(this)
            .setTitle("Choose a login")
            .setItems(labels) { _, which ->
                buildAndReturnDataset(list[which], vaultKey)
            }
            .setOnCancelListener { cancel() }
            .show()
    }

    private fun buildAndReturnDataset(cred: CachedCredential, vaultKey: ByteArray) {
        val password = try {
            CredentialCrypto.decryptCredential(cred.encryptedPayload, cred.iv, vaultKey).password
        } catch (_: Exception) {
            toastAndCancel("Could not decrypt this credential.")
            return
        }

        val builder = Dataset.Builder()
        usernameId?.let { id ->
            builder.setValue(id, AutofillValue.forText(cred.usernameHint), chip(cred.usernameHint))
        }
        passwordId?.let { id ->
            builder.setValue(id, AutofillValue.forText(password), chip("••••••••"))
        }

        val reply = android.content.Intent().apply {
            putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, builder.build())
        }
        setResult(RESULT_OK, reply)
        finish()
    }

    private fun chip(text: String) =
        RemoteViews(packageName, R.layout.autofill_chip).apply {
            setTextViewText(R.id.autofill_chip_text, text)
        }

    private fun cancel() {
        setResult(RESULT_CANCELED)
        finish()
    }

    private fun toastAndCancel(message: String) {
        android.widget.Toast.makeText(this, message, android.widget.Toast.LENGTH_LONG).show()
        cancel()
    }

    @Suppress("DEPRECATION")
    private fun intentExtra(key: String): AutofillId? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(key, AutofillId::class.java)
        } else {
            intent.getParcelableExtra(key)
        }
    }
}
