// Phase 4 — AES-256-GCM encryption/decryption
// Implemented in the next phase alongside the Add/Edit credential screens.

// What this will do:
//   encrypt(plaintext, masterPassword) → { encryptedPayload, iv }
//   decrypt(encryptedPayload, iv, masterPassword) → plaintext
//
// Key derivation: PBKDF2(masterPassword, salt, 310000 iterations) → 256-bit AES key
// Encryption:     AES-256-GCM with a random 96-bit nonce per operation
// The master password is never stored — only held in memory while the app is active.

class CryptoService {
  // TODO(Phase 4): implement encrypt and decrypt
}
