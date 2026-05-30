import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/credential.dart';
import 'crypto_service.dart';

/// Health status for a single credential.
/// Holds the [Credential] (so the UI can navigate to edit) but NEVER the
/// plaintext password — that is hashed for analysis and immediately discarded.
class CredentialHealth {
  final Credential credential;
  final bool weak;
  final bool reused;

  /// null  → breach check could not run (offline / HIBP unreachable)
  /// 0     → checked, not found in any breach
  /// >0    → number of times this password appears in known breaches
  final int? breachCount;

  CredentialHealth({
    required this.credential,
    required this.weak,
    required this.reused,
    required this.breachCount,
  });

  bool get breached => (breachCount ?? 0) > 0;
  bool get hasIssue => weak || reused || breached;
}

/// Aggregated report over the whole vault.
class HealthReport {
  final List<CredentialHealth> items;
  HealthReport(this.items);

  List<CredentialHealth> get weak     => items.where((i) => i.weak).toList();
  List<CredentialHealth> get reused   => items.where((i) => i.reused).toList();
  List<CredentialHealth> get breached => items.where((i) => i.breached).toList();

  /// True if at least one credential's breach status is known.
  bool get breachCheckAvailable => items.any((i) => i.breachCount != null);

  /// 0–100 overall score. Breaches weigh heaviest, then reuse, then weakness.
  int get score {
    if (items.isEmpty) return 100;
    var problems = 0;
    for (final i in items) {
      if (i.breached) {
        problems += 3;
      } else if (i.reused) {
        problems += 2;
      } else if (i.weak) {
        problems += 1;
      }
    }
    final maxProblems = items.length * 3;
    return (100 - (problems / maxProblems) * 100).round().clamp(0, 100);
  }
}

class PasswordHealthService {
  /// Analyses every credential's decrypted password for weakness, reuse, and
  /// known breaches. Decryption + hashing happen locally; only the first 5 hex
  /// chars of each password's SHA-1 hash are sent to HIBP (k-anonymity model),
  /// so the plaintext never leaves the device.
  static Future<HealthReport> analyze(
    List<Credential> credentials,
    Uint8List vaultKey, {
    bool checkBreaches = true,
  }) async {
    // 1. Decrypt — skip any credential encrypted with a different vault key.
    final decrypted = <(Credential, String)>[];
    for (final c in credentials) {
      try {
        final r = CryptoService.decryptCredential(
            c.encryptedPayload, c.iv, vaultKey);
        decrypted.add((c, r.password));
      } catch (_) {
        // Undecryptable — can't assess; leave out of the report.
      }
    }

    // 2. Reuse — count occurrences of each plaintext password.
    final countByPassword = <String, int>{};
    for (final (_, pw) in decrypted) {
      countByPassword[pw] = (countByPassword[pw] ?? 0) + 1;
    }

    // 3. Breach — one HIBP lookup per unique password (memoised).
    final breachByPassword = <String, int?>{};
    if (checkBreaches) {
      for (final pw in countByPassword.keys) {
        breachByPassword[pw] = await _hibpCount(pw);
      }
    }

    // 4. Build per-credential health.
    final items = decrypted.map((entry) {
      final (cred, pw) = entry;
      return CredentialHealth(
        credential:  cred,
        weak:        _isWeak(pw),
        reused:      (countByPassword[pw] ?? 0) > 1,
        breachCount: checkBreaches ? breachByPassword[pw] : null,
      );
    }).toList();

    return HealthReport(items);
  }

  // A password is weak if it is short OR uses fewer than 3 character classes
  // (lowercase / uppercase / digit / symbol).
  static bool _isWeak(String password) {
    if (password.length < 8) return true;
    var classes = 0;
    if (password.contains(RegExp(r'[a-z]')))       classes++;
    if (password.contains(RegExp(r'[A-Z]')))       classes++;
    if (password.contains(RegExp(r'[0-9]')))       classes++;
    if (password.contains(RegExp(r'[^a-zA-Z0-9]'))) classes++;
    return classes < 3;
  }

  /// Queries Have I Been Pwned's range API using k-anonymity.
  /// Returns the breach count, 0 if clean, or null if the check failed.
  static Future<int?> _hibpCount(String password) async {
    try {
      final hash   = sha1.convert(utf8.encode(password)).toString().toUpperCase();
      final prefix = hash.substring(0, 5);
      final suffix = hash.substring(5);

      final resp = await http
          .get(Uri.parse('https://api.pwnedpasswords.com/range/$prefix'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return null;

      for (final line in const LineSplitter().convert(resp.body)) {
        final parts = line.split(':');
        if (parts.length == 2 && parts[0].toUpperCase() == suffix) {
          return int.tryParse(parts[1].trim()) ?? 0;
        }
      }
      return 0; // checked, not found
    } catch (_) {
      return null; // offline / timeout — unknown
    }
  }
}
