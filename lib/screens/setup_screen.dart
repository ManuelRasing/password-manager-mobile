import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/master_password_provider.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  // Loading state while checking server for existing vault config
  bool _checking = true;
  String? _checkError; // non-null means server check failed (e.g. bad API key)
  // true  → vault already exists on server (new device / reinstall)
  // false → first-time setup (create new vault)
  bool _vaultExists = false;
  Map<String, String>? _existingConfig;

  final _formKey = GlobalKey<FormState>();
  final _passwordController  = TextEditingController();
  final _confirmController   = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm  = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _checkServer() async {
    setState(() { _checking = true; _checkError = null; });
    try {
      final config = await ApiService().getVaultConfig();
      if (!mounted) return;
      setState(() {
        _vaultExists    = config != null;
        _existingConfig = config;
        _checking       = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Surface the error — a wrong API key shows up here as "Invalid signature"
      setState(() {
        _checking    = false;
        _checkError  = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── First-time setup: create a brand-new vault ────────────────────────────
  Future<void> _createVault() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final result =
          await CryptoService.setupVault(_passwordController.text);

      await ApiService().putVaultConfig({
        'masterSalt':        result.masterSalt,
        'encryptedVaultKey': result.encryptedVaultKey,
        'vaultKeyIv':        result.vaultKeyIv,
      });

      await StorageService.setVaultSetup(true);
      if (!mounted) return;
      context.read<MasterPasswordProvider>().set(result.vaultKey);
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Setup failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── New-device unlock: vault exists, just derive the vault key ────────────
  Future<void> _unlockExisting() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final config = _existingConfig!;
      final Uint8List vaultKey = await CryptoService.unlockVault(
        _passwordController.text,
        config['masterSalt']!,
        config['encryptedVaultKey']!,
        config['vaultKeyIv']!,
      );

      await StorageService.setVaultSetup(true);
      if (!mounted) return;
      context.read<MasterPasswordProvider>().set(vaultKey);
      context.go('/');
    } on Exception catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Server check failed (wrong API key, network error, etc.)
    if (_checkError != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 24),
                const Text(
                  'Could not reach the server',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _checkError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Make sure your API key in Settings exactly matches the API_KEY environment variable on your server.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _checkServer,
                  child: const Text('Retry'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.go('/settings'),
                  child: const Text('Back to Settings'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 64),
                const Icon(Icons.lock_outline, size: 80, color: Colors.indigo),
                const SizedBox(height: 24),
                Text(
                  _vaultExists
                      ? 'Welcome Back'
                      : 'Set Master Password',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _vaultExists
                      ? 'Enter your master password to unlock your vault on this device.'
                      : 'This password encrypts all your credentials. It is never stored or '
                        'transmitted — if you forget it, your data cannot be recovered.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 40),
                // ── Password field ──────────────────────────────────────────
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText:
                        _vaultExists ? 'Master Password' : 'Master Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!_vaultExists && v.trim().length < 8) {
                      return 'Minimum 8 characters';
                    }
                    return null;
                  },
                ),
                // ── Confirm field (create mode only) ────────────────────────
                if (!_vaultExists) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (v.trim() != _passwordController.text.trim()) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : (_vaultExists ? _unlockExisting : _createVault),
                  child: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_vaultExists ? 'Unlock' : 'Set Password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
