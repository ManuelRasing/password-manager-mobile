import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage.
/// On Android: EncryptedSharedPreferences (backed by Android Keystore).
/// On iOS: Keychain.
class StorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _keyApiKey = 'api_key';
  static const _keyServerUrl = 'server_url';
  static const _keyMasterSalt = 'master_salt';
  static const _keyBiometricEnabled = 'biometric_enabled';
  static const _keyBiometricMasterPassword = 'biometric_master_password';

  // --- API Key ---
  static Future<String?> getApiKey() => _storage.read(key: _keyApiKey);
  static Future<void> setApiKey(String key) =>
      _storage.write(key: _keyApiKey, value: key);

  // --- Server URL ---
  static Future<String?> getServerUrl() => _storage.read(key: _keyServerUrl);
  static Future<void> setServerUrl(String url) =>
      _storage.write(key: _keyServerUrl, value: url);

  // --- Master Salt ---
  static Future<String?> getMasterSalt() => _storage.read(key: _keyMasterSalt);
  static Future<void> setMasterSalt(String salt) =>
      _storage.write(key: _keyMasterSalt, value: salt);

  // --- Biometric unlock ---
  static Future<bool> isBiometricEnabled() async {
    final v = await _storage.read(key: _keyBiometricEnabled);
    return v == 'true';
  }

  static Future<void> setBiometricEnabled(bool enabled) =>
      _storage.write(key: _keyBiometricEnabled, value: enabled.toString());

  /// The master password stored for biometric unlock.
  /// Only written when the user explicitly enables biometric unlock.
  static Future<String?> getBiometricMasterPassword() =>
      _storage.read(key: _keyBiometricMasterPassword);

  static Future<void> setBiometricMasterPassword(String password) =>
      _storage.write(key: _keyBiometricMasterPassword, value: password);

  static Future<void> clearBiometricMasterPassword() =>
      _storage.delete(key: _keyBiometricMasterPassword);

  // --- Setup check ---
  static Future<bool> isConfigured() async {
    final apiKey = await _storage.read(key: _keyApiKey);
    final serverUrl = await _storage.read(key: _keyServerUrl);
    return apiKey != null &&
        apiKey.isNotEmpty &&
        serverUrl != null &&
        serverUrl.isNotEmpty;
  }

  static Future<void> clearAll() => _storage.deleteAll();
}
