import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/services/crypto_service.dart';

void main() {
  // compute() spawns isolates; PBKDF2 at 310k iterations is the slow part.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('vault key lifecycle', () {
    test('setupVault → unlockVault round-trips to the same vault key', () async {
      final setup = await CryptoService.setupVault('correct horse battery');
      final unlocked = await CryptoService.unlockVault(
        'correct horse battery',
        setup.masterSalt,
        setup.encryptedVaultKey,
        setup.vaultKeyIv,
      );
      expect(unlocked, equals(setup.vaultKey));
    });

    test('unlockVault with the wrong password throws', () async {
      final setup = await CryptoService.setupVault('right-password');
      await expectLater(
        CryptoService.unlockVault(
          'wrong-password',
          setup.masterSalt,
          setup.encryptedVaultKey,
          setup.vaultKeyIv,
        ),
        throwsA(predicate((e) =>
            e.toString().contains('Wrong master password'))),
      );
    });

    test('rotateMasterPassword keeps the same vault key, new password unlocks',
        () async {
      final setup = await CryptoService.setupVault('old-password');
      final rotated =
          await CryptoService.rotateMasterPassword(setup.vaultKey, 'new-password');

      // New password unlocks to the SAME vault key (credentials need no re-encrypt)
      final unlocked = await CryptoService.unlockVault(
        'new-password',
        rotated.masterSalt,
        rotated.encryptedVaultKey,
        rotated.vaultKeyIv,
      );
      expect(unlocked, equals(setup.vaultKey));
    });

    test('old password no longer unlocks after rotation', () async {
      final setup = await CryptoService.setupVault('old-password');
      final rotated =
          await CryptoService.rotateMasterPassword(setup.vaultKey, 'new-password');
      await expectLater(
        CryptoService.unlockVault(
          'old-password',
          rotated.masterSalt,
          rotated.encryptedVaultKey,
          rotated.vaultKeyIv,
        ),
        throwsA(anything),
      );
    });
  });

  group('credential encrypt / decrypt', () {
    // A fixed 32-byte key avoids the PBKDF2 cost for these fast tests.
    final vaultKey =
        Uint8List.fromList(List<int>.generate(32, (i) => (i * 7) % 256));

    test('round-trips a password with no notes', () {
      final enc = CryptoService.encryptCredential('hunter2', null, vaultKey);
      final dec = CryptoService.decryptCredential(
          enc['encryptedPayload']!, enc['iv']!, vaultKey);
      expect(dec.password, 'hunter2');
      expect(dec.notes, isNull);
    });

    test('round-trips a password with notes', () {
      final enc = CryptoService.encryptCredential(
          'hunter2', 'recovery code: 1234', vaultKey);
      final dec = CryptoService.decryptCredential(
          enc['encryptedPayload']!, enc['iv']!, vaultKey);
      expect(dec.password, 'hunter2');
      expect(dec.notes, 'recovery code: 1234');
    });

    test('backward-compat: decrypts an old plain-string payload', () {
      // Old format — the ciphertext is just the raw password, not JSON.
      final enc = CryptoService.encrypt('legacy-password', vaultKey);
      final dec = CryptoService.decryptCredential(
          enc['encryptedPayload']!, enc['iv']!, vaultKey);
      expect(dec.password, 'legacy-password');
      expect(dec.notes, isNull);
    });

    test('decrypt throws on a tampered ciphertext (GCM tag mismatch)', () {
      final enc = CryptoService.encrypt('secret', vaultKey);
      // Flip the payload to a different valid-base64 blob.
      final tampered = enc['encryptedPayload']!.replaceRange(0, 4, 'AAAA');
      expect(
        () => CryptoService.decrypt(tampered, enc['iv']!, vaultKey),
        throwsA(anything),
      );
    });

    test('decrypt with the wrong key throws', () {
      final enc = CryptoService.encrypt('secret', vaultKey);
      final otherKey =
          Uint8List.fromList(List<int>.generate(32, (i) => (i * 3) % 256));
      expect(
        () => CryptoService.decrypt(
            enc['encryptedPayload']!, enc['iv']!, otherKey),
        throwsA(anything),
      );
    });
  });
}
