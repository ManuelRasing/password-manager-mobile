import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Holds the vault key in memory only — never written to disk.
///
/// The vault key is the true AES-256 encryption key for all credentials.
/// It is obtained by unlocking the vault (PBKDF2 + AES-GCM unwrap) and
/// discarded as soon as the app goes to the background.
class MasterPasswordProvider extends ChangeNotifier
    with WidgetsBindingObserver {
  Uint8List? _vaultKey;

  MasterPasswordProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Clear from memory when app goes to background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      clear();
    }
  }

  Uint8List? get vaultKey => _vaultKey;
  bool get isUnlocked => _vaultKey != null;

  void set(Uint8List vaultKey) {
    _vaultKey = vaultKey;
    notifyListeners();
  }

  void clear() {
    if (_vaultKey != null) {
      _vaultKey!.fillRange(0, _vaultKey!.length, 0); // zero bytes before GC
      _vaultKey = null;
      notifyListeners();
    }
  }
}
