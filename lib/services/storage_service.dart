import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage.
/// On Android: EncryptedSharedPreferences (backed by Android Keystore).
/// On iOS: Keychain.
class StorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // The biometric vault key gives direct access to all credentials — it must
  // never be included in iCloud backups (first_unlock_this_device = non-migratable).
  static const _bioIOSOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  static const _keyApiKey            = 'api_key';
  static const _keyUsername          = 'username';
  static const _keyServerUrl         = 'server_url';
  static const _keyVaultSetup        = 'vault_setup';         // local flag
  static const _keyBiometricEnabled  = 'biometric_enabled';
  static const _keyBiometricVaultKey = 'biometric_vault_key'; // base64 vault key
  static const _keyCachedCredentials = 'cached_credentials';  // JSON-encoded list

  // --- API Key ---
  static Future<String?> getApiKey() => _storage.read(key: _keyApiKey);
  static Future<void> setApiKey(String key) =>
      _storage.write(key: _keyApiKey, value: key);

  // --- Username (multi-user identifier sent in X-Username header) ---
  // Writing a *different* username drops the local credential cache — the
  // previous entries belong to a different account. Invariant lives here so
  // callers can't forget it.
  static Future<String?> getUsername() => _storage.read(key: _keyUsername);
  static Future<void> setUsername(String username) async {
    final previous = await _storage.read(key: _keyUsername);
    await _storage.write(key: _keyUsername, value: username);
    if (previous != null && previous != username) {
      await _storage.delete(key: _keyCachedCredentials);
    }
  }

  // --- Server URL ---
  static Future<String?> getServerUrl() => _storage.read(key: _keyServerUrl);
  static Future<void> setServerUrl(String url) =>
      _storage.write(key: _keyServerUrl, value: url);

  // --- Vault setup flag ---
  // Set to true after the vault config has been created and uploaded to the
  // server.  Used at startup to decide whether to show the setup screen.
  static Future<bool> isVaultSetup() async {
    final v = await _storage.read(key: _keyVaultSetup);
    return v == 'true';
  }

  static Future<void> setVaultSetup(bool value) =>
      _storage.write(key: _keyVaultSetup, value: value.toString());

  // --- Biometric unlock ---
  // Stores the vault key (base64-encoded) so biometric auth can restore the
  // session without a PBKDF2 round-trip.  The stored value is the vault key,
  // NOT the master password — it does not need to change when the master
  // password changes.
  static Future<bool> isBiometricEnabled() async {
    final v = await _storage.read(key: _keyBiometricEnabled);
    return v == 'true';
  }

  static Future<void> setBiometricEnabled(bool enabled) =>
      _storage.write(key: _keyBiometricEnabled, value: enabled.toString());

  static Future<String?> getBiometricVaultKey() =>
      _storage.read(key: _keyBiometricVaultKey, iOptions: _bioIOSOptions);

  static Future<void> setBiometricVaultKey(String base64Key) =>
      _storage.write(key: _keyBiometricVaultKey, value: base64Key,
          iOptions: _bioIOSOptions);

  static Future<void> clearBiometricVaultKey() =>
      _storage.delete(key: _keyBiometricVaultKey, iOptions: _bioIOSOptions);

  // --- Local credential cache ---
  // Stores the full credential list (server JSON shape) for offline access.
  // Each entry's `encryptedPayload` is still ciphertext — the cache itself
  // also lives in flutter_secure_storage (Keychain / EncryptedSharedPreferences).
  static Future<String?> getCachedCredentials() =>
      _storage.read(key: _keyCachedCredentials);

  static Future<void> setCachedCredentials(String jsonStr) =>
      _storage.write(key: _keyCachedCredentials, value: jsonStr);

  static Future<void> clearCachedCredentials() =>
      _storage.delete(key: _keyCachedCredentials);

  // --- Setup check (username + API key + server URL configured) ---
  static Future<bool> isConfigured() async {
    final apiKey    = await _storage.read(key: _keyApiKey);
    final username  = await _storage.read(key: _keyUsername);
    final serverUrl = await _storage.read(key: _keyServerUrl);
    return apiKey    != null && apiKey.isNotEmpty &&
           username  != null && username.isNotEmpty &&
           serverUrl != null && serverUrl.isNotEmpty;
  }

  static Future<void> clearAll() => _storage.deleteAll();
}
