package com.personal.password_manager.autofill

import android.util.Base64
import org.json.JSONObject
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Decrypted credential payload — mirrors Dart's decryptCredential() record. */
data class CredentialPayload(val password: String, val notes: String?)

/**
 * AES-256-GCM decryption that matches the Dart `encrypt` package exactly:
 *   - 12-byte IV (base64 in the `iv` field)
 *   - ciphertext and the 16-byte GCM tag are concatenated (ciphertext || tag)
 *     in the base64 `encryptedPayload`, which is exactly what
 *     Cipher("AES/GCM/NoPadding").doFinal() expects.
 */
object CredentialCrypto {
    /** Decrypts to plaintext. Throws on a wrong key / tampered data (tag mismatch). */
    fun decrypt(encryptedPayloadB64: String, ivB64: String, vaultKey: ByteArray): String {
        val ciphertext = Base64.decode(encryptedPayloadB64, Base64.DEFAULT)
        val iv = Base64.decode(ivB64, Base64.DEFAULT)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            SecretKeySpec(vaultKey, "AES"),
            GCMParameterSpec(128, iv), // 128-bit tag
        )
        return String(cipher.doFinal(ciphertext), Charsets.UTF_8)
    }

    /**
     * Decrypts and parses the payload. Backward-compatible with the old format
     * where the ciphertext was the raw password string (not JSON) — same
     * fallback as Dart's CryptoService.decryptCredential.
     */
    fun decryptCredential(
        encryptedPayloadB64: String,
        ivB64: String,
        vaultKey: ByteArray,
    ): CredentialPayload {
        val plaintext = decrypt(encryptedPayloadB64, ivB64, vaultKey)
        return try {
            val json = JSONObject(plaintext)
            val notes = if (json.has("notes")) json.optString("notes", null) else null
            CredentialPayload(json.getString("password"), notes?.ifEmpty { null })
        } catch (_: Exception) {
            CredentialPayload(plaintext, null) // old plain-string format
        }
    }
}
