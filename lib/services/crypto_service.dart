import 'dart:convert';
import 'dart:math';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

// ---------------------------------------------------------------------------
// PBKDF2 key derivation — top-level so compute() can use it off the UI thread.
// 310k iterations ≈ 1–2 s on device; running off-thread keeps the UI smooth.
// ---------------------------------------------------------------------------
Uint8List _deriveKeyIsolate(List<dynamic> args) {
  final password = args[0] as String;
  final salt = args[1] as Uint8List;
  final params = Pbkdf2Parameters(salt, 310000, 32);
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  kdf.init(params);
  return kdf.process(Uint8List.fromList(utf8.encode(password)));
}

// ---------------------------------------------------------------------------
// CryptoService — vault-key (envelope encryption) model
//
// Architecture (mirrors Bitwarden's design):
//
//   masterPassword + masterSalt  ──PBKDF2──►  masterKey   (ephemeral, never stored)
//   masterKey + vaultKey         ──AES-GCM──► encryptedVaultKey  (stored on server)
//   vaultKey + credential        ──AES-GCM──► encryptedPayload   (stored on server)
//
// The vaultKey is a random 256-bit key generated once and kept in memory
// while the app is unlocked.  Changing the master password only re-wraps
// the vaultKey — credentials never need to be re-encrypted.
// ---------------------------------------------------------------------------
class CryptoService {
  // ── Key derivation ────────────────────────────────────────────────────────

  static Future<Uint8List> _deriveMasterKey(
          String password, Uint8List salt) async =>
      compute(_deriveKeyIsolate, [password, salt]);

  static Uint8List _randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));
  }

  // ── Vault setup ───────────────────────────────────────────────────────────
  // Call once when the user first creates their master password.
  // Returns the three values to upload to the server plus the raw vaultKey
  // to keep in memory (MasterPasswordProvider).

  static Future<({
    String masterSalt,
    String encryptedVaultKey,
    String vaultKeyIv,
    Uint8List vaultKey,
  })> setupVault(String masterPassword) async {
    final salt = _randomBytes(32);
    final vaultKey = _randomBytes(32); // true random encryption key
    final masterKey = await _deriveMasterKey(masterPassword, salt);
    final wrapped = _wrapKey(masterKey, vaultKey);
    return (
      masterSalt: base64.encode(salt),
      encryptedVaultKey: wrapped.$1,
      vaultKeyIv: wrapped.$2,
      vaultKey: vaultKey,
    );
  }

  // ── Vault unlock ──────────────────────────────────────────────────────────
  // Derive the master key from the entered password, then decrypt the vault
  // key.  Throws if the password is wrong (AES-GCM tag mismatch).
  // Works on any device — all inputs come from the server.

  static Future<Uint8List> unlockVault(
    String masterPassword,
    String masterSaltB64,
    String encryptedVaultKeyB64,
    String vaultKeyIvB64,
  ) async {
    final salt = base64.decode(masterSaltB64);
    final masterKey = await _deriveMasterKey(masterPassword, salt);
    return _unwrapKey(masterKey, encryptedVaultKeyB64, vaultKeyIvB64);
  }

  // ── Master-password rotation ──────────────────────────────────────────────
  // Re-wraps the vaultKey with a new master password + fresh salt.
  // The vaultKey itself does NOT change — credentials need no re-encryption.

  static Future<({
    String masterSalt,
    String encryptedVaultKey,
    String vaultKeyIv,
  })> rotateMasterPassword(
    Uint8List vaultKey,
    String newPassword,
  ) async {
    final newSalt = _randomBytes(32);
    final newMasterKey = await _deriveMasterKey(newPassword, newSalt);
    final wrapped = _wrapKey(newMasterKey, vaultKey);
    return (
      masterSalt: base64.encode(newSalt),
      encryptedVaultKey: wrapped.$1,
      vaultKeyIv: wrapped.$2,
    );
  }

  // ── Credential encrypt / decrypt (synchronous) ────────────────────────────
  // Uses the vaultKey directly — no PBKDF2 needed here.
  //
  // New format: encryptedPayload = AES-GCM( JSON { "password": "...", "notes": "..." } )
  // Old format (backward-compat): encryptedPayload = AES-GCM( plainPasswordString )

  /// Encrypts a credential payload (password + optional notes) into a single ciphertext.
  static Map<String, String> encryptCredential(
    String password,
    String? notes,
    Uint8List vaultKey,
  ) {
    final payload = jsonEncode({
      'password': password,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return encrypt(payload, vaultKey);
  }

  /// Decrypts a credential payload and returns password + notes.
  /// Backward-compatible: handles both old plain-string and new JSON formats.
  static ({String password, String? notes}) decryptCredential(
    String encryptedPayload,
    String ivBase64,
    Uint8List vaultKey,
  ) {
    final plaintext = decrypt(encryptedPayload, ivBase64, vaultKey);
    try {
      final json = jsonDecode(plaintext) as Map<String, dynamic>;
      return (
        password: json['password'] as String? ?? plaintext,
        notes:    json['notes']    as String?,
      );
    } catch (_) {
      // Old format — the plaintext is the password itself
      return (password: plaintext, notes: null);
    }
  }

  /// Low-level encrypt: AES-256-GCM of any string. Used by encryptCredential
  /// and by the vault key wrapping helpers above.
  static Map<String, String> encrypt(String plaintext, Uint8List vaultKey) {
    final iv = enc.IV.fromSecureRandom(12);
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(vaultKey), mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    return {'encryptedPayload': encrypted.base64, 'iv': iv.base64};
  }

  /// Low-level decrypt. Throws 'Decryption failed' on wrong key / corrupted data.
  static String decrypt(
    String encryptedPayload,
    String ivBase64,
    Uint8List vaultKey,
  ) {
    try {
      final iv = enc.IV.fromBase64(ivBase64);
      final encrypter =
          enc.Encrypter(enc.AES(enc.Key(vaultKey), mode: enc.AESMode.gcm));
      return encrypter.decrypt(
          enc.Encrypted.fromBase64(encryptedPayload), iv: iv);
    } catch (_) {
      throw Exception('Decryption failed');
    }
  }

  // ── Internal AES-256-GCM key-wrapping helpers ─────────────────────────────
  // Only used to wrap/unwrap the 32-byte vaultKey — synchronous and fast.

  static (String ciphertextB64, String ivB64) _wrapKey(
      Uint8List masterKey, Uint8List vaultKey) {
    final iv = enc.IV.fromSecureRandom(12);
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(masterKey), mode: enc.AESMode.gcm));
    final encrypted = encrypter.encryptBytes(vaultKey.toList(), iv: iv);
    return (encrypted.base64, iv.base64);
  }

  static Uint8List _unwrapKey(
      Uint8List masterKey, String ciphertextB64, String ivB64) {
    try {
      final iv = enc.IV.fromBase64(ivB64);
      final encrypter =
          enc.Encrypter(enc.AES(enc.Key(masterKey), mode: enc.AESMode.gcm));
      final bytes = encrypter
          .decryptBytes(enc.Encrypted.fromBase64(ciphertextB64), iv: iv);
      return Uint8List.fromList(bytes);
    } catch (_) {
      throw Exception('Wrong master password');
    }
  }
}
