import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';

/// Shows the master-password dialog.
///
/// Fetches the vault config from the server, derives the master key, and
/// decrypts the vault key.  Returns the raw vault key on success, or null
/// if the user cancels.  Shows an inline error on wrong password.
Future<Uint8List?> showMasterPasswordDialog(BuildContext context) {
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _MasterPasswordDialog(),
  );
}

class _MasterPasswordDialog extends StatefulWidget {
  const _MasterPasswordDialog();

  @override
  State<_MasterPasswordDialog> createState() => _MasterPasswordDialogState();
}

class _MasterPasswordDialogState extends State<_MasterPasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text.trim();
    if (password.isEmpty) return;

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      final config = await ApiService().getVaultConfig();
      if (!mounted) return;
      if (config == null) {
        setState(() => _error = 'Vault not configured — please complete setup.');
        return;
      }

      final vaultKey = await CryptoService.unlockVault(
        password,
        config['masterSalt']!,
        config['encryptedVaultKey']!,
        config['vaultKeyIv']!,
      );

      if (mounted) Navigator.pop(context, vaultKey);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Incorrect master password');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Master Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            enabled: !_working,
            decoration: InputDecoration(
              labelText: 'Enter master password',
              border: const OutlineInputBorder(),
              errorText: _error,
              suffixIcon: IconButton(
                icon:
                    Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _working ? null : _submit(),
          ),
          if (_working) ...[
            const SizedBox(height: 16),
            const Row(
              children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Unlocking…', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _working ? null : _submit,
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}
