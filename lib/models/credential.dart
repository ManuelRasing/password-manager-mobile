class Credential {
  final String id;
  final String siteName;
  final String usernameHint;
  final String? url;              // plaintext website URL (nullable)
  final String encryptedPayload;  // AES-256-GCM ciphertext of JSON {password, notes?}
  final String iv;
  final DateTime createdAt;
  final DateTime updatedAt;

  Credential({
    required this.id,
    required this.siteName,
    required this.usernameHint,
    this.url,
    required this.encryptedPayload,
    required this.iv,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Credential.fromJson(Map<String, dynamic> json) {
    return Credential(
      id:               json['id']               as String,
      siteName:         json['siteName']          as String,
      usernameHint:     json['usernameHint']      as String? ?? '',
      url:              json['url']               as String?,
      encryptedPayload: json['encryptedPayload']  as String,
      iv:               json['iv']                as String,
      createdAt:        DateTime.parse(json['createdAt'] as String),
      updatedAt:        DateTime.parse(json['updatedAt'] as String),
    );
  }

  // Used for local cache serialisation — mirrors the server response shape.
  Map<String, dynamic> toJson() => {
    'id':               id,
    'siteName':         siteName,
    'usernameHint':     usernameHint,
    if (url != null) 'url': url,
    'encryptedPayload': encryptedPayload,
    'iv':               iv,
    'createdAt':        createdAt.toIso8601String(),
    'updatedAt':        updatedAt.toIso8601String(),
  };
}
