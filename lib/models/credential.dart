class Credential {
  final String id;
  final String siteName;
  final String usernameHint;
  final String encryptedPayload;
  final String iv;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Decrypted password — only ever held in memory, never stored or sent
  String? plaintextPassword;

  Credential({
    required this.id,
    required this.siteName,
    required this.usernameHint,
    required this.encryptedPayload,
    required this.iv,
    required this.createdAt,
    required this.updatedAt,
    this.plaintextPassword,
  });

  factory Credential.fromJson(Map<String, dynamic> json) {
    return Credential(
      id: json['id'] as String,
      siteName: json['siteName'] as String,
      usernameHint: json['usernameHint'] as String? ?? '',
      encryptedPayload: json['encryptedPayload'] as String,
      iv: json['iv'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  // Used when sending to the server — never includes plaintextPassword
  Map<String, dynamic> toJson() {
    return {
      'siteName': siteName,
      'usernameHint': usernameHint,
      'encryptedPayload': encryptedPayload,
      'iv': iv,
    };
  }
}
