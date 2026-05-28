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

### Phase 5 — Polish & Biometrics
- **Password generator** bottom sheet on AddScreen — length slider, charset toggles (A–Z, a–z, 0–9, !@#), regenerate, copy
- **Search bar** on HomeScreen — live client-side filter by site name or username hint
- **Biometric unlock** (`local_auth`) — Face ID / fingerprint to restore master password session after app backgrounds
  - Opt-in toggle in Settings; requires entering master password + biometric confirmation to enable
  - Auto-triggers on app resume if enabled
  - Falls back to manual master password entry if biometric fails
- `BiometricService` wrapper around `local_auth`
- `StorageService` extended with biometric enable flag + encrypted master password storage
- Android: `FlutterFragmentActivity` + biometric permissions in `AndroidManifest.xml`
- iOS: `NSFaceIDUsageDescription` in `Info.plist`

### Phase 7 — Vault Key Model (envelope encryption)
- **`CryptoService`** rewritten: `setupVault`, `unlockVault`, `rotateMasterPassword`, `encrypt`, `decrypt`
  - Vault key is a random 256-bit key generated once; master key (PBKDF2) only wraps it
  - Credential encrypt/decrypt is now synchronous (vault key already in memory — no PBKDF2 per operation)
- **`MasterPasswordProvider`** now stores `Uint8List vaultKey` instead of a password string
- **`StorageService`** simplified: removed per-device salt + verifier keys; biometric now stores vault key (base64), not the master password — survives master-password changes
- **`ApiService`** extended: `getVaultConfig()` and `putVaultConfig()` methods
- **`MasterPasswordDialog`** fetches vault config from server, derives master key, decrypts vault key; returns `Uint8List` on success
- **`SetupScreen`** checks server on load: create mode (new vault) vs unlock mode (existing vault on new device / reinstall)
- **`ChangeMasterPasswordScreen`** simplified: re-wraps vault key only — no credential re-encryption
- **`main.dart`** uses `isVaultSetup()` local flag backed by `vault_setup` in secure storage
- Multi-device and reinstall safe: vault config lives on server, any device can unlock with the master password

### Phase 6 — Master Password Setup Flow
- `SetupScreen` — dedicated first-launch screen with enter + confirm fields (min 8 chars); calls `CryptoService.createVerifier` then navigates to Home
- `ChangeMasterPasswordScreen` — re-encrypts every credential in-place with a progress indicator; only commits the new salt + verifier after all server updates succeed
- `MasterPasswordDialog` upgraded — verifies entered password against the stored verifier (PBKDF2 comparison) before returning; shows inline "Verifying…" state and "Incorrect master password" error
- `main.dart` — startup now checks `isMasterPasswordSetup()`; routes to `/setup` if not yet configured; `/change-password` route added
- Settings screen — "Change Master Password" tile added to Security section
- Security storage: `verifier_ciphertext` + `verifier_iv` stored in flutter_secure_storage alongside the master salt

### Bug Fix — DELETE 400 Bad Request
- `ApiService._signedHeaders`: no longer sends `Content-Type: application/json` when there is no request body — sending it on a bodyless DELETE caused Fastify to attempt `JSON.parse('')` and return 400 before the route handler ran
- `ApiService._assertSuccess`: now surfaces Fastify's `message` field (e.g. "body/id must match format uuid") instead of just the generic `error` text ("Bad Request"), making future errors much easier to diagnose
