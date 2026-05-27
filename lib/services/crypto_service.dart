import 'dart:convert';
import 'dart:math';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'storage_service.dart';

// The known plaintext encrypted to create / verify against the verifier.
const _verifyPlaintext = 'pm-verify-v1';

// ---------------------------------------------------------------------------
// Top-level isolate function for PBKDF2 (must be top-level for compute()).
// 310k iterations ≈ 1-2s on device; off-thread so UI stays responsive.
// ---------------------------------------------------------------------------
Uint8List _deriveKeyIsolate(List<dynamic> args) {
  final password = args[0] as String;
  final salt = args[1] as Uint8List;
  final params = Pbkdf2Parameters(salt, 310000, 32);
  final keyDerivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  keyDerivator.init(params);
  return keyDerivator.process(Uint8List.fromList(utf8.encode(password)));
}

class CryptoService {
  // -------------------------------------------------------------------------
  // Key derivation
  // -------------------------------------------------------------------------

  static Future<Uint8List> _deriveKey(
          String masterPassword, Uint8List salt) async =>
      compute(_deriveKeyIsolate, [masterPassword, salt]);

  // -------------------------------------------------------------------------
  // Salt helpers
  // -------------------------------------------------------------------------

  static Future<Uint8List> _getOrCreateSalt() async {
    final existing = await StorageService.getMasterSalt();
    if (existing != null) return base64.decode(existing);
    final salt = _randomBytes(32);
    await StorageService.setMasterSalt(base64.encode(salt));
    return salt;
  }

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  // -------------------------------------------------------------------------
  // Verifier — encrypt a known string to confirm the master password
  // without having to attempt decrypting a real credential.
  // -------------------------------------------------------------------------

  /// Call once after the user sets their master password.
  static Future<void> createVerifier(String masterPassword) async {
    final salt = await _getOrCreateSalt();
    final keyBytes = await _deriveKey(masterPassword, salt);
    final key = enc.Key(keyBytes);
    final iv = enc.IV.fromSecureRandom(12);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(_verifyPlaintext, iv: iv);
    await StorageService.setVerifierCiphertext(encrypted.base64);
    await StorageService.setVerifierIv(iv.base64);
  }

  /// Returns true if the entered password matches the stored verifier.
  static Future<bool> verifyMasterPassword(String masterPassword) async {
    try {
      final ciphertext = await StorageService.getVerifierCiphertext();
      final ivStr = await StorageService.getVerifierIv();
      final saltStr = await StorageService.getMasterSalt();
      if (ciphertext == null || ivStr == null || saltStr == null) return false;

      final salt = base64.decode(saltStr);
      final keyBytes = await _deriveKey(masterPassword, salt);
      final key = enc.Key(keyBytes);
      final iv = enc.IV.fromBase64(ivStr);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
      final decrypted = encrypter.decrypt(
          enc.Encrypted.fromBase64(ciphertext), iv: iv);
      return decrypted == _verifyPlaintext;
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Encrypt
  // -------------------------------------------------------------------------

  static Future<Map<String, String>> encrypt(
      String plaintext, String masterPassword) async {
    final salt = await _getOrCreateSalt();
    final keyBytes = await _deriveKey(masterPassword, salt);
    final key = enc.Key(keyBytes);
    final iv = enc.IV.fromSecureRandom(12);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return {'encryptedPayload': encrypted.base64, 'iv': iv.base64};
  }

  // -------------------------------------------------------------------------
  // Decrypt
  // -------------------------------------------------------------------------

  static Future<String> decrypt(
      String encryptedPayload, String ivBase64, String masterPassword) async {
    final saltStr = await StorageService.getMasterSalt();
    if (saltStr == null) throw Exception('No encryption salt found on device');
    final salt = base64.decode(saltStr);
    final keyBytes = await _deriveKey(masterPassword, salt);
    final key = enc.Key(keyBytes);
    final iv = enc.IV.fromBase64(ivBase64);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    try {
      return encrypter.decrypt(enc.Encrypted.fromBase64(encryptedPayload),
          iv: iv);
    } catch (_) {
      throw Exception('Wrong master password or corrupted data');
    }
  }

  // -------------------------------------------------------------------------
  // Change master password
  //
  // Strategy to minimise data loss risk:
  //   1. Decrypt ALL credentials with old key first (abort if any fail)
  //   2. Generate new salt + derive new key
  //   3. Re-encrypt all in memory
  //   4. Push all updates to the server
  //   5. Only then write new salt + verifier to local storage
  // -------------------------------------------------------------------------

  static Future<void> changeMasterPassword({
    required String oldPassword,
    required String newPassword,
    required Future<List<dynamic>> Function() fetchCredentials,
    required Future<void> Function(String id, Map<String, dynamic> body)
        updateCredential,
    required void Function(String message) onProgress,
  }) async {
    onProgress('Verifying current password…');
    final isValid = await verifyMasterPassword(oldPassword);
    if (!isValid) throw Exception('Current master password is incorrect');

    onProgress('Loading credentials…');
    final rawList = await fetchCredentials();

    // Step 1 — decrypt everything with old key first
    onProgress('Decrypting credentials…');
    final oldSaltStr = await StorageService.getMasterSalt();
    if (oldSaltStr == null) throw Exception('No salt found');
    final oldSalt = base64.decode(oldSaltStr);
    final oldKeyBytes = await _deriveKey(oldPassword, oldSalt);
    final oldKey = enc.Key(oldKeyBytes);
    final encrypterOld =
        enc.Encrypter(enc.AES(oldKey, mode: enc.AESMode.gcm));

    final plaintexts = <String, String>{}; // id → plaintext
    for (final raw in rawList) {
      final id = raw['id'] as String;
      final ciphertext = raw['encryptedPayload'] as String;
      final ivStr = raw['iv'] as String;
      try {
        final decrypted = encrypterOld.decrypt(
            enc.Encrypted.fromBase64(ciphertext),
            iv: enc.IV.fromBase64(ivStr));
        plaintexts[id] = decrypted;
      } catch (_) {
        throw Exception(
            'Failed to decrypt "${ raw['siteName'] }" — password change aborted. No data was modified.');
      }
    }

    // Step 2 — new salt + new key
    onProgress('Generating new encryption key…');
    final newSalt = _randomBytes(32);
    final newKeyBytes = await _deriveKey(newPassword, newSalt);
    final newKey = enc.Key(newKeyBytes);
    final encrypterNew =
        enc.Encrypter(enc.AES(newKey, mode: enc.AESMode.gcm));

    // Step 3 — re-encrypt in memory
    final reEncrypted = <String, Map<String, String>>{};
    for (final entry in plaintexts.entries) {
      final iv = enc.IV.fromSecureRandom(12);
      final encrypted =
          encrypterNew.encrypt(entry.value, iv: iv);
      reEncrypted[entry.key] = {
        'encryptedPayload': encrypted.base64,
        'iv': iv.base64,
      };
    }

    // Step 4 — push updates to server
    int done = 0;
    for (final raw in rawList) {
      final id = raw['id'] as String;
      final newPayload = reEncrypted[id]!;
      onProgress(
          'Updating credentials… (${++done}/${rawList.length})');
      await updateCredential(id, {
        'siteName': raw['siteName'],
        'usernameHint': raw['usernameHint'] ?? '',
        'encryptedPayload': newPayload['encryptedPayload']!,
        'iv': newPayload['iv']!,
      });
    }

    // Step 5 — commit new salt + verifier only after all server updates succeed
    onProgress('Saving new key…');
    await StorageService.setMasterSalt(base64.encode(newSalt));
    await _writeVerifier(newPassword, newSalt);

    // Update biometric stored password if enabled
    final bioEnabled = await StorageService.isBiometricEnabled();
    if (bioEnabled) {
      await StorageService.setBiometricMasterPassword(newPassword);
    }
  }

  // Internal: write verifier using an explicit salt (used during password change)
  static Future<void> _writeVerifier(
      String masterPassword, Uint8List salt) async {
    final keyBytes = await _deriveKey(masterPassword, salt);
    final key = enc.Key(keyBytes);
    final iv = enc.IV.fromSecureRandom(12);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(_verifyPlaintext, iv: iv);
    await StorageService.setVerifierCiphertext(encrypted.base64);
    await StorageService.setVerifierIv(iv.base64);
  }
}
