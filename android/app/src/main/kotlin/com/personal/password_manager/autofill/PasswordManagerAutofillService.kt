package com.personal.password_manager.autofill

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.app.assist.AssistStructure
import android.service.autofill.AutofillService
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveInfo
import android.view.View
import android.view.autofill.AutofillId
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import com.personal.password_manager.R

/**
 * System autofill service. Runs in its own process (no access to Flutter's
 * Dart memory), so it returns an authentication intent: tapping the suggestion
 * launches [AutofillAuthActivity], which biometric-unlocks, reads the shared
 * vault, decrypts, and returns the chosen dataset.
 */
@RequiresApi(Build.VERSION_CODES.O)
class PasswordManagerAutofillService : AutofillService() {

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }

        val parsed = parseStructure(structure)
        if (parsed.passwordId == null && parsed.usernameId == null) {
            callback.onSuccess(null) // nothing fillable here
            return
        }

        val autofillIds = listOfNotNull(parsed.usernameId, parsed.passwordId).toTypedArray()

        // Presentation shown in the autofill dropdown.
        val presentation = RemoteViews(packageName, R.layout.autofill_chip).apply {
            setTextViewText(R.id.autofill_chip_text, "Unlock Password Manager")
        }

        // Authentication intent → AutofillAuthActivity does the real work.
        val authIntent = Intent(this, AutofillAuthActivity::class.java).apply {
            putExtra(EXTRA_USERNAME_ID, parsed.usernameId)
            putExtra(EXTRA_PASSWORD_ID, parsed.passwordId)
            putExtra(EXTRA_WEB_DOMAIN, parsed.webDomain)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            authIntent.hashCode(),
            authIntent,
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_CANCEL_CURRENT,
        )

        val response = FillResponse.Builder()
            .setAuthentication(autofillIds, pendingIntent.intentSender, presentation)
            .setSaveInfo(
                SaveInfo.Builder(
                    SaveInfo.SAVE_DATA_TYPE_USERNAME or SaveInfo.SAVE_DATA_TYPE_PASSWORD,
                    autofillIds,
                ).build(),
            )
            .build()

        callback.onSuccess(response)
    }

    // Saving new credentials from the browser is out of scope for v1 — the user
    // adds credentials in the app. Accept the request so no error is shown.
    override fun onSaveRequest(request: android.service.autofill.SaveRequest, callback: android.service.autofill.SaveCallback) {
        callback.onSuccess()
    }

    // ── Structure parsing ─────────────────────────────────────────────────────
    data class ParsedFields(
        val usernameId: AutofillId?,
        val passwordId: AutofillId?,
        val webDomain: String?,
    )

    private fun parseStructure(structure: AssistStructure): ParsedFields {
        var usernameId: AutofillId? = null
        var passwordId: AutofillId? = null
        var webDomain: String? = null

        fun visit(node: AssistStructure.ViewNode) {
            node.webDomain?.let { if (it.isNotBlank()) webDomain = it }

            val hints = node.autofillHints
            val isFillable = node.autofillId != null &&
                node.autofillType == View.AUTOFILL_TYPE_TEXT

            if (isFillable) {
                val hintStr = (hints?.joinToString(" ") ?: "").lowercase()
                val idEntry = (node.idEntry ?: "").lowercase()
                val hintText = (node.hint ?: "").lowercase()
                val haystack = "$hintStr $idEntry $hintText"
                val inputType = node.inputType

                val looksLikePassword = haystack.contains("password") ||
                    haystack.contains("passwd") ||
                    (inputType and android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD) != 0 ||
                    (inputType and android.text.InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD) != 0

                val looksLikeUsername = haystack.contains("user") ||
                    haystack.contains("email") ||
                    haystack.contains("login") ||
                    haystack.contains("phone")

                if (looksLikePassword && passwordId == null) {
                    passwordId = node.autofillId
                } else if (looksLikeUsername && usernameId == null) {
                    usernameId = node.autofillId
                }
            }

            for (i in 0 until node.childCount) visit(node.getChildAt(i))
        }

        for (i in 0 until structure.windowNodeCount) {
            visit(structure.getWindowNodeAt(i).rootViewNode)
        }
        return ParsedFields(usernameId, passwordId, webDomain)
    }

    companion object {
        const val EXTRA_USERNAME_ID = "extra_username_id"
        const val EXTRA_PASSWORD_ID = "extra_password_id"
        const val EXTRA_WEB_DOMAIN = "extra_web_domain"
    }
}
