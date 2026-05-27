import 'package:flutter/material.dart';
import '../models/credential.dart';

// Phase 4 will implement encryption here.
// For now this screen is a shell — the save button is wired up but
// encryption (CryptoService) is not yet implemented.

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

  bool get _isEditing => widget.credential != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _siteNameController.text = widget.credential!.siteName;
      _usernameHintController.text = widget.credential!.usernameHint;
      // Password field stays empty — user must re-enter to update (Phase 4)
    }
  }

  @override
  void dispose() {
    _siteNameController.dispose();
    _usernameHintController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    // TODO(Phase 4): encrypt _passwordController.text with CryptoService,
    // then call ApiService().createCredential() or updateCredential().
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Encryption coming in Phase 4 — save not yet wired up')),
    );
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
                validator: _isEditing
                    ? null
                    : (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _save,
                child: Text(_isEditing ? 'Update' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
