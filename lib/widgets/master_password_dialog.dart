import 'package:flutter/material.dart';

/// Shows a dialog prompting for the master password.
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Master Password'),
      content: TextField(
        controller: _controller,
        obscureText: _obscure,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'Enter master password',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}
