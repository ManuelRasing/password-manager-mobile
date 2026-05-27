import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/credential.dart';
import '../providers/master_password_provider.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../widgets/master_password_dialog.dart';

class AddScreen extends StatefulWidget {
  final Credential? credential; // non-null = edit mode

  const AddScreen({super.key, this.credential});

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _siteNameController = TextEditingController();
  final _usernameHintController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _saving = false;
  bool get _isEditing => widget.credential != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _siteNameController.text = widget.credential!.siteName;
      _usernameHintController.text = widget.credential!.usernameHint;
    }
  }

  @override
  void dispose() {
    _siteNameController.dispose();
    _usernameHintController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Require password on create; optional on edit
    final passwordInput = _passwordController.text.trim();
    if (!_isEditing && passwordInput.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password is required')));
      return;
    }

    // Get or prompt for master password
    final mp = context.read<MasterPasswordProvider>();
    String? masterPassword = mp.password;
    if (masterPassword == null) {
      if (!mounted) return;
      masterPassword = await showMasterPasswordDialog(context);
      if (masterPassword == null) return; // user cancelled
      mp.set(masterPassword);
    }

    setState(() => _saving = true);
    try {
      String encryptedPayload;
      String iv;

      if (passwordInput.isNotEmpty) {
        // Encrypt the new password
        final result =
            await CryptoService.encrypt(passwordInput, masterPassword);
        encryptedPayload = result['encryptedPayload']!;
        iv = result['iv']!;
      } else {
        // Edit mode with no new password — keep existing ciphertext
        encryptedPayload = widget.credential!.encryptedPayload;
        iv = widget.credential!.iv;
      }

      final body = {
        'siteName': _siteNameController.text.trim(),
        'usernameHint': _usernameHintController.text.trim(),
        'encryptedPayload': encryptedPayload,
        'iv': iv,
      };

      if (_isEditing) {
        await ApiService().updateCredential(widget.credential!.id, body);
      } else {
        await ApiService().createCredential(body);
      }

      if (!mounted) return;
      Navigator.pop(context, true); // signal HomeScreen to reload
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Credential' : 'New Credential'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _siteNameController,
                decoration: const InputDecoration(
                  labelText: 'Site / App name',
                  hintText: 'e.g. GitHub',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameHintController,
                decoration: const InputDecoration(
                  labelText: 'Username / Email (hint)',
                  hintText: 'e.g. me@email.com',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: _isEditing
                      ? 'New password (leave blank to keep current)'
                      : 'Password',
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              const Text(
                'Password is encrypted on this device before being sent to the server.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isEditing ? 'Update' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
