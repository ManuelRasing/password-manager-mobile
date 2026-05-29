import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/credential.dart';
import '../providers/master_password_provider.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../widgets/master_password_dialog.dart';
import '../widgets/password_generator_sheet.dart';

class AddScreen extends StatefulWidget {
  final Credential? credential; // non-null = edit mode

  const AddScreen({super.key, this.credential});

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  final _formKey              = GlobalKey<FormState>();
  final _siteNameController   = TextEditingController();
  final _usernameController   = TextEditingController();
  final _urlController        = TextEditingController();
  final _passwordController   = TextEditingController();
  final _notesController      = TextEditingController();

  bool _saving       = false;
  bool _prefilling   = false; // true while decrypting on edit-mode open
  bool get _isEditing => widget.credential != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _siteNameController.text  = widget.credential!.siteName;
      _usernameController.text  = widget.credential!.usernameHint;
      _urlController.text       = widget.credential!.url ?? '';
      _prefillDecrypted();
    }
  }

  @override
  void dispose() {
    _siteNameController.dispose();
    _usernameController.dispose();
    _urlController.dispose();
    _passwordController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ── Decrypt-on-open for edit mode ─────────────────────────────────────────
  Future<void> _prefillDecrypted() async {
    setState(() => _prefilling = true);
    try {
      final vaultKey = await _ensureVaultKey();
      if (vaultKey == null || !mounted) return;

      final result = CryptoService.decryptCredential(
        widget.credential!.encryptedPayload,
        widget.credential!.iv,
        vaultKey,
      );
      if (mounted) {
        setState(() {
          _passwordController.text = result.password;
          _notesController.text    = result.notes ?? '';
        });
      }
    } catch (_) {
      // Decryption failed (different vault key). Fields stay blank.
    } finally {
      if (mounted) setState(() => _prefilling = false);
    }
  }

  // ── Vault key helper ──────────────────────────────────────────────────────
  Future<Uint8List?> _ensureVaultKey() async {
    final mp = context.read<MasterPasswordProvider>();
    if (mp.isUnlocked) return mp.vaultKey;
    if (!mounted) return null;
    final vaultKey = await showMasterPasswordDialog(context);
    if (vaultKey != null && mounted) mp.set(vaultKey);
    return vaultKey;
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final passwordInput = _passwordController.text;
    if (!_isEditing && passwordInput.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password is required')));
      return;
    }

    final vaultKey = await _ensureVaultKey();
    if (vaultKey == null) return;

    setState(() => _saving = true);
    try {
      String encryptedPayload;
      String iv;

      if (_isEditing && passwordInput.trim().isEmpty) {
        // Edit mode — no new password entered, keep existing ciphertext
        encryptedPayload = widget.credential!.encryptedPayload;
        iv               = widget.credential!.iv;
      } else {
        // New or edited password — always encrypt notes together with password
        final result = CryptoService.encryptCredential(
          passwordInput.trim(),
          _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          vaultKey,
        );
        encryptedPayload = result['encryptedPayload']!;
        iv               = result['iv']!;
      }

      final urlValue = _urlController.text.trim();
      final body = {
        'siteName':         _siteNameController.text.trim(),
        'usernameHint':     _usernameController.text.trim(),
        if (urlValue.isNotEmpty) 'url': urlValue,
        'encryptedPayload': encryptedPayload,
        'iv':               iv,
      };

      if (_isEditing) {
        await ApiService().updateCredential(widget.credential!.id, body);
      } else {
        await ApiService().createCredential(body);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Error: ${e.toString().replaceFirst('Exception: ', '')}')));
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
      body: _prefilling
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Site name
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

                    // Username hint
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username / Email (hint)',
                        hintText: 'e.g. me@email.com',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // URL (plaintext)
                    TextFormField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'Website URL (optional)',
                        hintText: 'https://example.com',
                        border: const OutlineInputBorder(),
                        suffixIcon: _urlController.text.trim().isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.open_in_browser),
                                tooltip: 'Open URL',
                                onPressed: () async {
                                  final uri = Uri.tryParse(
                                      _urlController.text.trim());
                                  if (uri != null && await canLaunchUrl(uri)) {
                                    launchUrl(uri,
                                        mode: LaunchMode.externalApplication);
                                  }
                                },
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Password
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: _isEditing
                            ? 'Password (pre-filled — change to update)'
                            : 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.auto_fix_high),
                          tooltip: 'Generate password',
                          onPressed: () async {
                            final generated =
                                await showPasswordGeneratorSheet(context);
                            if (generated != null) {
                              _passwordController.text = generated;
                            }
                          },
                        ),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),

                    // Notes (encrypted with password)
                    TextFormField(
                      controller: _notesController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Notes (optional, encrypted)',
                        hintText: _isEditing
                            ? 'Leave blank to keep existing notes'
                            : 'e.g. Security question, PIN, SSH passphrase…',
                        border: const OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Password and notes are encrypted on this device before being sent to the server.',
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
                                  strokeWidth: 2, color: Colors.white))
                          : Text(_isEditing ? 'Update' : 'Save'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
