import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/master_password_provider.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';

class ChangeMasterPasswordScreen extends StatefulWidget {
  const ChangeMasterPasswordScreen({super.key});

  @override
  State<ChangeMasterPasswordScreen> createState() =>
      _ChangeMasterPasswordScreenState();
}

class _ChangeMasterPasswordScreenState
    extends State<ChangeMasterPasswordScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _oldController  = TextEditingController();
  final _newController  = TextEditingController();
  final _confController = TextEditingController();

  bool _obscureOld  = true;
  bool _obscureNew  = true;
  bool _obscureConf = true;
  bool _working     = false;
  String? _progress;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confController.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _working  = true;
      _progress = 'Fetching vault config…';
    });

    try {
      // 1. Fetch vault config from server
      final config = await ApiService().getVaultConfig();
      if (config == null) throw Exception('Vault not configured');

      // 2. Verify current password and get vault key
      if (mounted) setState(() => _progress = 'Verifying current password…');
      final Uint8List vaultKey = await CryptoService.unlockVault(
        _oldController.text,
        config['masterSalt']!,
        config['encryptedVaultKey']!,
        config['vaultKeyIv']!,
      );

      // 3. Re-wrap the vault key with the new master password
      if (mounted) setState(() => _progress = 'Generating new key…');
      final newConfig = await CryptoService.rotateMasterPassword(
        vaultKey,
        _newController.text,
      );

      // 4. Upload new vault config — only this one call, no credential changes
      if (mounted) setState(() => _progress = 'Saving…');
      await ApiService().putVaultConfig({
        'masterSalt':        newConfig.masterSalt,
        'encryptedVaultKey': newConfig.encryptedVaultKey,
        'vaultKeyIv':        newConfig.vaultKeyIv,
      });

      if (!mounted) return;
      // Vault key is unchanged — provider stays valid, biometric stays valid
      context.read<MasterPasswordProvider>().set(vaultKey);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Master password changed successfully')),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() { _working = false; _progress = null; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Master Password'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Only the master password changes — your credentials are not '
                're-encrypted because the vault key stays the same.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              _passwordField(
                controller: _oldController,
                label: 'Current Password',
                obscure: _obscureOld,
                onToggle: () => setState(() => _obscureOld = !_obscureOld),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              _passwordField(
                controller: _newController,
                label: 'New Password',
                obscure: _obscureNew,
                onToggle: () => setState(() => _obscureNew = !_obscureNew),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v.trim().length < 8) return 'Minimum 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _passwordField(
                controller: _confController,
                label: 'Confirm New Password',
                obscure: _obscureConf,
                onToggle: () => setState(() => _obscureConf = !_obscureConf),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v.trim() != _newController.text.trim()) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              if (_working) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Text(_progress ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
              ],
              FilledButton(
                onPressed: _working ? null : _change,
                child: _working
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Change Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      enabled: !_working,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
          onPressed: onToggle,
        ),
      ),
      validator: validator,
    );
  }
}
