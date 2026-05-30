package com.personal.password_manager.autofill

import android.content.Context
import android.security.keystore.KeyProperties
import android.security.keystore.KeyGenParameterSpec
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray

/** A single credential as stored in the local cache (server JSON shape). */
data class CachedCredential(
    val id: String,
    val siteName: String,
    val usernameHint: String,
    val url: String?,
    val encryptedPayload: String,
    val iv: String,
)

/**
 * Reads the same EncryptedSharedPreferences file that flutter_secure_storage
 * writes from Dart. The configuration here MUST match the plugin exactly:
 *
 *   file         = "FlutterSecureStorage"
 *   master key   = MasterKey.DEFAULT_MASTER_KEY_ALIAS (GCM, 256-bit)
 *   key scheme   = AES256_SIV   value scheme = AES256_GCM
 *   stored key   = "<PREFIX>_<logicalKey>"
 *
 * Verified against flutter_secure_storage 9.2.4
 * (android/.../FlutterSecureStorage.java).
 */
object VaultReader {
    // flutter_secure_storage prepends this fixed prefix to every logical key.
    private const val KEY_PREFIX =
        "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg"
    private const val PREFS_FILE = "FlutterSecureStorage"

    private fun prefixed(key: String) = "${KEY_PREFIX}_$key"

    private fun prefs(context: Context) = run {
        val masterKey = MasterKey.Builder(context)
            .setKeyGenParameterSpec(
                KeyGenParameterSpec.Builder(
                    MasterKey.DEFAULT_MASTER_KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setKeySize(256)
                    .build(),
            )
            .build()

        EncryptedSharedPreferences.create(
            context,
            PREFS_FILE,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    /**
     * Returns the raw vault key bytes, or null if biometric unlock was never
     * enabled (the key only lives here when the user opts into biometrics).
     */
    fun readVaultKey(context: Context): ByteArray? {
        return try {
            val b64 = prefs(context)
                .getString(prefixed("biometric_vault_key"), null) ?: return null
            Base64.decode(b64, Base64.DEFAULT)
        } catch (_: Exception) {
            null
        }
    }

    /** Returns the cached credential list, or an empty list if none/unavailable. */
    fun readCachedCredentials(context: Context): List<CachedCredential> {
        return try {
            val json = prefs(context)
                .getString(prefixed("cached_credentials"), null) ?: return emptyList()
            parse(json)
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun parse(json: String): List<CachedCredential> {
        val arr = JSONArray(json)
        val out = ArrayList<CachedCredential>(arr.length())
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            out.add(
                CachedCredential(
                    id = o.getString("id"),
                    siteName = o.getString("siteName"),
                    usernameHint = o.optString("usernameHint", ""),
                    url = if (o.isNull("url")) null else o.optString("url", null),
                    encryptedPayload = o.getString("encryptedPayload"),
                    iv = o.getString("iv"),
                ),
            )
        }
        return out
    }
}
