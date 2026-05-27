import 'dart:convert';
import 'dart:math';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'storage_service.dart';

// ---------------------------------------------------------------------------
// Top-level function — required by compute() to run in a separate isolate.
// PBKDF2 at 310k iterations takes ~1-2s; running it off the UI thread
// keeps the app responsive during encrypt/decrypt operations.
// ---------------------------------------------------------------------------
Uint8List _deriveKeyIsolate(List<dynamic> args) {
  final password = args[0] as String;
  final salt = args[1] as Uint8List;

  final params = Pbkdf2Parameters(salt, 310000, 32); // 32 bytes = 256-bit key
  final keyDerivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  keyDerivator.init(params);
  return keyDerivator.process(Uint8List.fromList(utf8.encode(password)));
}

class CryptoService {
  // -------------------------------------------------------------------------
  // Key derivation
  // -------------------------------------------------------------------------

  static Future<Uint8List> _deriveKey(
      String masterPassword, Uint8List salt) async {
    return compute(_deriveKeyIsolate, [masterPassword, salt]);
  }

  // -------------------------------------------------------------------------
  // Salt management — one per device, stored in secure storage.
  // Generated on first encrypt call and reused for all subsequent operations.
  // -------------------------------------------------------------------------

  static Future<Uint8List> _getOrCreateSalt() async {
    final existing = await StorageService.getMasterSalt();
    if (existing != null) return base64.decode(existing);

    // First time — generate a 32-byte cryptographically secure salt
    final rng = Random.secure();
    final salt =
        Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
    await StorageService.setMasterSalt(base64.encode(salt));
    return salt;
  }

  // -------------------------------------------------------------------------
  // Encrypt
  // Returns { 'encryptedPayload': base64, 'iv': base64 }
  // Each call uses a fresh 96-bit random nonce — never reuse an IV with GCM.
  // -------------------------------------------------------------------------

  static Future<Map<String, String>> encrypt(
      String plaintext, String masterPassword) async {
    final salt = await _getOrCreateSalt();
    final keyBytes = await _deriveKey(masterPassword, salt);

    final key = enc.Key(keyBytes);
    final iv = enc.IV.fromSecureRandom(12); // 96-bit nonce
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);

    return {
      'encryptedPayload': encrypted.base64,
      'iv': iv.base64,
    };
  }

  // -------------------------------------------------------------------------
  // Decrypt
  // Throws if the master password is wrong (GCM auth tag mismatch).
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
}
