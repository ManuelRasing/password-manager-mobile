import 'package:flutter/material.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';

/// Shows a dialog prompting for the master password.
/// If a verifier is stored, the entered password is verified before returning.
/// Returns the entered password, or null if the user cancels.
Future<String?> showMasterPasswordDialog(BuildContext context) {
  return showDialog<String>(
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
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;

    // Only verify if a verifier exists (i.e. master password has been set up)
    final isSetup = await StorageService.isMasterPasswordSetup();
    if (!isSetup) {
      // No verifier yet — just return as-is (shouldn't normally reach here)
      if (mounted) Navigator.pop(context, value);
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    final correct = await CryptoService.verifyMasterPassword(value);

    if (!mounted) return;
    if (correct) {
      Navigator.pop(context, value);
    } else {
      setState(() {
        _verifying = false;
        _error = 'Incorrect master password';
      });
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
            enabled: !_verifying,
            decoration: InputDecoration(
              labelText: 'Enter master password',
              border: const OutlineInputBorder(),
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _verifying ? null : _submit(),
          ),
          if (_verifying) ...[
            const SizedBox(height: 16),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Verifying…', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _verifying ? null : () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _verifying ? null : _submit,
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}
