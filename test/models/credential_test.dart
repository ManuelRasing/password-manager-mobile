import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/models/credential.dart';

void main() {
  group('Credential.fromJson', () {
    final base = {
      'id': 'abc',
      'siteName': 'GitHub',
      'usernameHint': 'me@example.com',
      'url': 'https://github.com',
      'encryptedPayload': 'cipher',
      'iv': 'nonce',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-02T00:00:00.000Z',
    };

    test('parses a full record', () {
      final c = Credential.fromJson(base);
      expect(c.id, 'abc');
      expect(c.siteName, 'GitHub');
      expect(c.usernameHint, 'me@example.com');
      expect(c.url, 'https://github.com');
      expect(c.encryptedPayload, 'cipher');
      expect(c.iv, 'nonce');
      expect(c.createdAt, DateTime.parse('2026-01-01T00:00:00.000Z'));
    });

    test('defaults missing usernameHint to empty string', () {
      final json = Map<String, dynamic>.from(base)..remove('usernameHint');
      final c = Credential.fromJson(json);
      expect(c.usernameHint, '');
    });

    test('allows missing url (null)', () {
      final json = Map<String, dynamic>.from(base)..remove('url');
      final c = Credential.fromJson(json);
      expect(c.url, isNull);
    });
  });

  group('Credential.toJson', () {
    test('round-trips through fromJson preserving all fields', () {
      final original = Credential(
        id: 'id1',
        siteName: 'Site',
        usernameHint: 'user',
        url: 'https://x.com',
        encryptedPayload: 'cipher',
        iv: 'nonce',
        createdAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
        updatedAt: DateTime.parse('2026-01-02T00:00:00.000Z'),
      );
      final restored = Credential.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.siteName, original.siteName);
      expect(restored.usernameHint, original.usernameHint);
      expect(restored.url, original.url);
      expect(restored.encryptedPayload, original.encryptedPayload);
      expect(restored.iv, original.iv);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('omits url when null', () {
      final c = Credential(
        id: 'id1',
        siteName: 'Site',
        usernameHint: '',
        url: null,
        encryptedPayload: 'cipher',
        iv: 'nonce',
        createdAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
        updatedAt: DateTime.parse('2026-01-02T00:00:00.000Z'),
      );
      expect(c.toJson().containsKey('url'), isFalse);
    });
  });
}
