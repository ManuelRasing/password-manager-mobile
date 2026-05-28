import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/credential.dart';
import 'storage_service.dart';

class ApiService {
  // ---------------------------------------------------------------------------
  // HMAC-SHA256 signing
  // Matches server: HMAC(apiKey, METHOD|PATH|TIMESTAMP|BODY_SHA256)
  // ---------------------------------------------------------------------------

  String _hashBody(String body) {
    return sha256.convert(utf8.encode(body)).toString();
  }

  String _computeHmac(
    String secret,
    String method,
    String path,
    String timestamp,
    String bodyHash,
  ) {
    final message = '${method.toUpperCase()}|$path|$timestamp|$bodyHash';
    final key = utf8.encode(secret);
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(message)).toString();
  }

  Future<Map<String, String>> _signedHeaders(
    String method,
    String path, {
    Object? body,
  }) async {
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API key not configured. Go to Settings.');
    }

    final timestamp =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final bodyStr = body != null ? jsonEncode(body) : '';
    final bodyHash = _hashBody(bodyStr);
    final signature = _computeHmac(apiKey, method, path, timestamp, bodyHash);

    return {
      // Only set Content-Type when there is a body — sending it on a bodyless
      // DELETE causes Fastify to attempt JSON.parse('') → 400 Bad Request.
      if (body != null) 'Content-Type': 'application/json',
      'X-Timestamp': timestamp,
      'X-Signature': signature,
    };
  }

  Future<String> get _baseUrl async {
    final url = await StorageService.getServerUrl();
    return (url != null && url.isNotEmpty)
        ? url.replaceAll(RegExp(r'/$'), '') // strip trailing slash
        : 'https://password-manager-server-9shr.onrender.com';
  }

  // ---------------------------------------------------------------------------
  // Credentials CRUD
  // ---------------------------------------------------------------------------

  Future<List<Credential>> getCredentials() async {
    const path = '/credentials';
    final base = await _baseUrl;
    final headers = await _signedHeaders('GET', path);

    final response = await http.get(Uri.parse('$base$path'), headers: headers);
    _assertSuccess(response, 200);

    final List<dynamic> data = jsonDecode(response.body);
    return data.map((json) => Credential.fromJson(json)).toList();
  }

  Future<Credential> createCredential(Map<String, dynamic> body) async {
    const path = '/credentials';
    final base = await _baseUrl;
    final headers = await _signedHeaders('POST', path, body: body);

    final response = await http.post(
      Uri.parse('$base$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    _assertSuccess(response, 201);
    return Credential.fromJson(jsonDecode(response.body));
  }

  Future<Credential> updateCredential(
      String id, Map<String, dynamic> body) async {
    final path = '/credentials/$id';
    final base = await _baseUrl;
    final headers = await _signedHeaders('PUT', path, body: body);

    final response = await http.put(
      Uri.parse('$base$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    _assertSuccess(response, 200);
    return Credential.fromJson(jsonDecode(response.body));
  }

  Future<void> deleteCredential(String id) async {
    final path = '/credentials/$id';
    final base = await _baseUrl;
    final headers = await _signedHeaders('DELETE', path);

    final response =
        await http.delete(Uri.parse('$base$path'), headers: headers);
    _assertSuccess(response, 204);
  }

  // ---------------------------------------------------------------------------
  // Vault config
  // ---------------------------------------------------------------------------

  /// Returns the stored vault config, or null if it has never been set up (404).
  Future<Map<String, String>?> getVaultConfig() async {
    const path = '/vault-config';
    final base = await _baseUrl;
    final headers = await _signedHeaders('GET', path);

    final response =
        await http.get(Uri.parse('$base$path'), headers: headers);
    if (response.statusCode == 404) return null;
    _assertSuccess(response, 200);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'masterSalt':        data['masterSalt']        as String,
      'encryptedVaultKey': data['encryptedVaultKey'] as String,
      'vaultKeyIv':        data['vaultKeyIv']        as String,
    };
  }

  /// Creates or replaces the vault config on the server.
  Future<void> putVaultConfig(Map<String, String> config) async {
    const path = '/vault-config';
    final base = await _baseUrl;
    final headers = await _signedHeaders('PUT', path, body: config);

    final response = await http.put(
      Uri.parse('$base$path'),
      headers: headers,
      body: jsonEncode(config),
    );
    _assertSuccess(response, 200);
  }

  // ---------------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> backupToGoogleDrive() async {
    const path = '/backup/google-drive';
    final base = await _baseUrl;
    final headers = await _signedHeaders('POST', path);

    final response = await http.post(Uri.parse('$base$path'), headers: headers);
    _assertSuccess(response, 200);
    return jsonDecode(response.body);
  }

  // ---------------------------------------------------------------------------
  // Connection test — used in Settings.
  // Returns null on success, or an error message string on failure.
  // Tests both network reachability (/health) and HMAC auth (/credentials).
  // ---------------------------------------------------------------------------

  Future<String?> testConnection() async {
    try {
      final base = await _baseUrl;

      // 1. Network reachability
      final healthResp = await http
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 10));
      if (healthResp.statusCode != 200) {
        return 'Server unreachable (${healthResp.statusCode})';
      }

      // 2. HMAC authentication — a GET /credentials verifies the API key
      const path = '/credentials';
      final headers = await _signedHeaders('GET', path);
      final authResp = await http
          .get(Uri.parse('$base$path'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (authResp.statusCode == 401) {
        return 'API key is incorrect — check it matches your server\'s API_KEY';
      }
      if (authResp.statusCode != 200) {
        return 'Auth check failed (${authResp.statusCode})';
      }

      return null; // success
    } on Exception catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    } catch (_) {
      return 'Could not reach server';
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _assertSuccess(http.Response response, int expectedStatus) {
    if (response.statusCode != expectedStatus) {
      final body = jsonDecode(response.body);
      // Fastify error shape: { statusCode, error (HTTP text), message (details) }
      // Prefer 'message' for specifics; fall back to 'error'; last resort: status code.
      throw Exception(
        body['message'] ?? body['error'] ?? 'Request failed (${response.statusCode})',
      );
    }
  }
}
