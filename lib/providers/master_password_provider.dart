import 'package:flutter/material.dart';

/// Holds the master password in memory only — never written to disk.
///
/// Automatically clears when the app goes to background (paused state).
/// This ensures the password is not accessible if the device is locked
/// or the app is switched away from.
class MasterPasswordProvider extends ChangeNotifier
    with WidgetsBindingObserver {
  String? _password;

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

  String? get password => _password;
  bool get isUnlocked => _password != null;

  void set(String password) {
    _password = password;
    notifyListeners();
  }

  void clear() {
    if (_password != null) {
      _password = null;
      notifyListeners();
    }
  }
}
