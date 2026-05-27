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
  final _formKey = GlobalKey<FormState>();
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _working = false;
  String? _progress;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _working = true;
      _progress = 'Starting…';
    });
    try {
      final api = ApiService();
      await CryptoService.changeMasterPassword(
        oldPassword: _oldController.text,
        newPassword: _newController.text,
        fetchCredentials: () async {
          final creds = await api.getCredentials();
          // Build raw maps that include id (needed by changeMasterPassword)
          return creds
              .map((c) => {
                    'id': c.id,
                    'siteName': c.siteName,
                    'usernameHint': c.usernameHint,
                    'encryptedPayload': c.encryptedPayload,
                    'iv': c.iv,
                  })
              .toList();
        },
        updateCredential: (id, body) => api.updateCredential(id, body),
        onProgress: (msg) {
          if (mounted) setState(() => _progress = msg);
        },
      );

      if (!mounted) return;
      context.read<MasterPasswordProvider>().set(_newController.text);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Master password changed successfully')),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _progress = null;
        });
      }
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
                'All credentials will be re-encrypted with your new password. '
                'This may take a moment.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              // ── Current password ──────────────────────────────────────────
              TextFormField(
                controller: _oldController,
                obscureText: _obscureOld,
                enabled: !_working,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureOld ? Icons.visibility : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscureOld = !_obscureOld),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              // ── New password ──────────────────────────────────────────────
              TextFormField(
                controller: _newController,
                obscureText: _obscureNew,
                enabled: !_working,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscureNew ? Icons.visibility : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v.trim().length < 8) return 'Minimum 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // ── Confirm new password ──────────────────────────────────────
              TextFormField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                enabled: !_working,
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (v.trim() != _newController.text.trim()) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              // ── Progress indicator ────────────────────────────────────────
              if (_working) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Text(
                  _progress ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
              ],
              FilledButton(
                onPressed: _working ? null : _change,
                child: _working
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Change Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
