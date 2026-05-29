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
  static const _keyServerUrl         = 'server_url';
  static const _keyVaultSetup        = 'vault_setup';         // local flag
  static const _keyBiometricEnabled  = 'biometric_enabled';
  static const _keyBiometricVaultKey = 'biometric_vault_key'; // base64 vault key

  // --- API Key ---
  static Future<String?> getApiKey() => _storage.read(key: _keyApiKey);
  static Future<void> setApiKey(String key) =>
      _storage.write(key: _keyApiKey, value: key);

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

  // --- Setup check (API key + server URL configured) ---
  static Future<bool> isConfigured() async {
    final apiKey    = await _storage.read(key: _keyApiKey);
    final serverUrl = await _storage.read(key: _keyServerUrl);
    return apiKey    != null && apiKey.isNotEmpty &&
           serverUrl != null && serverUrl.isNotEmpty;
  }

  static Future<void> clearAll() => _storage.deleteAll();
}
