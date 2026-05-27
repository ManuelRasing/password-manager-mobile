# Password Manager — Mobile

Flutter app (iOS + Android) for the personal password manager.

## Tech Stack

| Layer | Tech |
|-------|------|
| Framework | Flutter 3.x (Dart) |
| Navigation | go_router 14 |
| Secure storage | flutter_secure_storage 9 (Android Keystore / iOS Keychain) |
| HMAC signing | crypto 3 (sha256) |
| Encryption | encrypt 5 + pointycastle 3 (Phase 4) |

---

## Project Structure

```
lib/
├── main.dart                   # Entry point, GoRouter setup
├── models/
│   └── credential.dart         # Credential data model
├── services/
│   ├── api_service.dart         # HMAC-signed HTTP client
│   ├── storage_service.dart     # flutter_secure_storage wrapper
│   └── crypto_service.dart      # AES-256-GCM stub (Phase 4)
└── screens/
    ├── home_screen.dart         # Credential list + delete + backup
    ├── add_screen.dart          # Add/edit form shell (Phase 4 wires encryption)
    └── settings_screen.dart     # Server URL + API key config + connection test
```

---

## First-Launch Flow

On first launch the app has no API key stored → redirects automatically to **Settings**.

Enter:
- **Server URL** — your Render service URL (e.g. `https://password-manager-server-9shr.onrender.com`)
- **API Key** — the 64-char hex key from your Render environment variables

Tap **Test Connection** to verify, then **Save**.

---

## Security Model

### HMAC Request Signing

The raw API key is **never sent over the network**. Every request is signed:

```
X-Timestamp: <unix epoch seconds>
X-Signature: HMAC-SHA256(apiKey, METHOD|PATH|TIMESTAMP|BODY_SHA256)
```

Implemented in `api_service.dart` — mirrors `src/lib/hmac.ts` on the server.

### Secure Storage

| What | Where |
|------|-------|
| API key | Android Keystore / iOS Keychain via `flutter_secure_storage` |
| Server URL | Same |
| Master salt | Same (used in Phase 4) |
| Master password | Never stored — memory only (Phase 4) |

---

## Running Locally

```bash
flutter pub get
flutter run
```

---

## Dart ↔ TypeScript Cheat Sheet

| TypeScript | Dart |
|-----------|------|
| `interface Credential {}` | `class Credential {}` |
| `const x: string` | `final String x` |
| `async/await` | identical |
| `axios.get(url)` | `http.get(Uri.parse(url))` |
| `JSON.parse/stringify` | `jsonDecode/jsonEncode` |
| `?.` optional chaining | identical |
| `array.filter()` | `list.where()` |
| `array.map()` | `list.map()` |
| `localStorage` | `flutter_secure_storage` |

---

## Changelog

### Phase 3 — Flutter Scaffold
- Flutter project created (`com.personal.password_manager`)
- Android `minSdk` bumped to 23 for `flutter_secure_storage`
- `StorageService` — secure API key + server URL + master salt storage
- `ApiService` — full HMAC-SHA256 signed HTTP client (GET/POST/PUT/DELETE/backup)
- `Credential` model with `fromJson`/`toJson`
- `HomeScreen` — credential list, delete with confirm dialog, backup trigger
- `AddScreen` — form shell (save wired to encryption in Phase 4)
- `SettingsScreen` — server URL + API key input with live connection test
- `main.dart` — GoRouter with auto-redirect to Settings on first launch
- `CryptoService` stub ready for Phase 4

### Phase 4 — Encryption
- `CryptoService` — AES-256-GCM encrypt/decrypt via `encrypt` + `pointycastle`
- PBKDF2 key derivation: 310,000 iterations, SHA-256, 256-bit key, runs in background isolate via `compute()`
- Per-device salt generated on first encrypt, stored in `flutter_secure_storage`
- `MasterPasswordProvider` — holds master password in memory, auto-clears on app background (`AppLifecycleState.paused`)
- `MasterPasswordDialog` — reusable prompt widget
- `AddScreen` — save button encrypts password before calling `ApiService`; edit mode preserves existing ciphertext if password field is empty
- `HomeScreen` — tap credential → decrypt in background → reveal in modal bottom sheet with copy button
- Wrong master password caught gracefully; clears cached password and shows error

### Phase 5 — UI Polish _(upcoming)_
- Password generator
- Search / filter credentials
- Biometric unlock (Face ID / fingerprint) to restore cached master password
