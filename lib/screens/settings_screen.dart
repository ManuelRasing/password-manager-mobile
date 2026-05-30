import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/master_password_provider.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';
import '../services/storage_service.dart';
import '../widgets/master_password_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey             = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _usernameController  = TextEditingController();
  final _apiKeyController    = TextEditingController();

  bool _saving  = false;
  bool _testing = false;
  String? _testResult;

  bool _biometricAvailable = false;
  bool _biometricEnabled   = false;
  bool _togglingBiometric  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url          = await StorageService.getServerUrl();
    final username     = await StorageService.getUsername();
    final key          = await StorageService.getApiKey();
    final bioAvailable = await BiometricService.isAvailable();
    final bioEnabled   = await StorageService.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _serverUrlController.text =
          url ?? 'https://password-manager-server-9shr.onrender.com';
      _usernameController.text  = username ?? '';
      _apiKeyController.text    = key ?? '';
      _biometricAvailable       = bioAvailable;
      _biometricEnabled         = bioEnabled;
    });
  }

  // Persist the three credentials needed for HMAC + user lookup.
  // setUsername() handles cache invalidation on username change internally.
  Future<void> _persistCredentials() async {
    await Future.wait([
      StorageService.setServerUrl(_serverUrlController.text.trim()),
      StorageService.setUsername(_usernameController.text.trim()),
      StorageService.setApiKey(_apiKeyController.text.trim()),
    ]);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await _persistCredentials();
    setState(() => _saving = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Settings saved')));
    final vaultReady = await StorageService.isVaultSetup();
    if (!mounted) return;
    context.go(vaultReady ? '/' : '/setup');
  }

  Future<void> _testConnection() async {
    setState(() { _testing = true; _testResult = null; });
    // Save first so ApiService reads the values just entered
    await _persistCredentials();
    final error = await ApiService().testConnection();
    setState(() {
      _testing    = false;
      _testResult = error ?? 'Connected & API key verified ✓';
    });
  }

  Future<void> _toggleBiometric(bool enable) async {
    setState(() => _togglingBiometric = true);
    try {
      if (enable) {
        // Get vault key from provider or unlock now
        Uint8List? vaultKey =
            context.read<MasterPasswordProvider>().vaultKey;
        if (vaultKey == null) {
          vaultKey = await showMasterPasswordDialog(context);
          if (vaultKey == null || !mounted) return;
          context.read<MasterPasswordProvider>().set(vaultKey);
        }

        // Confirm with biometric before storing the vault key
        final ok = await BiometricService.authenticate(
            'Confirm to enable biometric unlock');
        if (!ok || !mounted) return;

        await StorageService.setBiometricVaultKey(base64.encode(vaultKey));
        await StorageService.setBiometricEnabled(true);
        setState(() => _biometricEnabled = true);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Biometric unlock enabled')));
        }
      } else {
        await StorageService.clearBiometricVaultKey();
        await StorageService.setBiometricEnabled(false);
        setState(() => _biometricEnabled = false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Biometric unlock disabled')));
        }
      }
    } finally {
      if (mounted) setState(() => _togglingBiometric = false);
    }
  }

  // Opens the Android system autofill-service picker so the user can select
  // this app. Android only; no-op elsewhere.
  Future<void> _openAutofillSettings() async {
    if (!Platform.isAndroid) return;
    const intent = AndroidIntent(
      action: 'android.settings.REQUEST_SET_AUTOFILL_SERVICE',
      data: 'package:com.personal.password_manager',
    );
    try {
      await intent.launch();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not open autofill settings. Set it manually: System '
                'Settings → Passwords & accounts → Autofill service.')));
      }
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Server configuration ──────────────────────────────────
              const Text('Server Configuration',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://your-server.onrender.com',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'Your username on this server',
                  border: OutlineInputBorder(),
                ),
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: _testing ? null : _testConnection,
                child: _testing
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Test Connection'),
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 8),
                Text(
                  _testResult!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _testResult!.startsWith('Connected')
                        ? Colors.green
                        : Colors.orange,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),

              // ── Security ─────────────────────────────────────────────
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              const Text('Security',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.health_and_safety),
                title: const Text('Password Health'),
                subtitle: const Text(
                    'Check for weak, reused, and breached passwords'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/password-health'),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_reset),
                title: const Text('Change Master Password'),
                subtitle: const Text(
                    'Re-wraps the vault key — credentials are unaffected'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/change-password'),
              ),
              if (_biometricAvailable) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Biometric Unlock'),
                  subtitle: const Text(
                      'Use Face ID or fingerprint to restore your session after backgrounding the app'),
                  value: _biometricEnabled,
                  onChanged: _togglingBiometric
                      ? null
                      : (v) => _toggleBiometric(v),
                ),
              ],
              if (Platform.isAndroid) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.password),
                  title: const Text('Set up Autofill'),
                  subtitle: const Text(
                      'Fill passwords in other apps. Requires Biometric Unlock to be enabled.'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: _openAutofillSettings,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
