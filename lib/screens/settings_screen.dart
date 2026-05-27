import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();

  bool _saving = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await StorageService.getServerUrl();
    final key = await StorageService.getApiKey();
    setState(() {
      _serverUrlController.text =
          url ?? 'https://password-manager-server-9shr.onrender.com';
      _apiKeyController.text = key ?? '';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await StorageService.setServerUrl(_serverUrlController.text.trim());
    await StorageService.setApiKey(_apiKeyController.text.trim());
    setState(() => _saving = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
    context.go('/');
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    // Temporarily write values so ApiService picks them up during the test
    await StorageService.setServerUrl(_serverUrlController.text.trim());
    await StorageService.setApiKey(_apiKeyController.text.trim());
    final ok = await ApiService().checkHealth();
    setState(() {
      _testing = false;
      _testResult = ok ? 'Connected successfully' : 'Could not reach server';
    });
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
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
              const Text(
                'Server Configuration',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
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
                        : Colors.red,
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
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
