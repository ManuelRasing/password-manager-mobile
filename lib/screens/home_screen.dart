import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/credential.dart';
import '../providers/master_password_provider.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../widgets/master_password_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Credential> _credentials = [];
  bool _loading = true;
  String? _error;

  // Search
  bool _searchActive = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<Credential> get _filtered => _searchQuery.isEmpty
      ? _credentials
      : _credentials
          .where((c) =>
              c.siteName
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ||
              c.usernameHint
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()))
          .toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _searchController.addListener(
        () => setState(() => _searchQuery = _searchController.text));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  // ── App lifecycle: auto-unlock via biometric on resume ────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResumed();
  }

  Future<void> _onResumed() async {
    final mp = context.read<MasterPasswordProvider>();
    if (mp.isUnlocked) return;

    final bioEnabled = await StorageService.isBiometricEnabled();
    if (!mounted) return;

    if (bioEnabled) {
      final authenticated =
          await BiometricService.authenticate('Unlock Password Manager');
      if (!mounted) return;
      if (authenticated) {
        final storedB64 = await StorageService.getBiometricVaultKey();
        if (storedB64 != null && mounted) {
          mp.set(base64.decode(storedB64));
          return; // unlocked — done
        }
      }
    }

    // Biometric cancelled / unavailable — fall back to manual dialog
    if (!mounted) return;
    final vaultKey = await showMasterPasswordDialog(context);
    if (vaultKey != null && mounted) mp.set(vaultKey);
  }

  // ── Data loading ──────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final credentials = await ApiService().getCredentials();
      setState(() => _credentials = credentials);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Unlock helper ─────────────────────────────────────────────────────────
  // Called before any operation that needs the vault key.
  // Biometric was already tried by _onResumed; here we go straight to dialog.
  Future<Uint8List?> _ensureUnlocked() async {
    final mp = context.read<MasterPasswordProvider>();
    if (mp.isUnlocked) return mp.vaultKey;
    if (!mounted) return null;
    final vaultKey = await showMasterPasswordDialog(context);
    if (vaultKey != null && mounted) mp.set(vaultKey);
    return vaultKey;
  }

  // ── Credential actions ────────────────────────────────────────────────────
  Future<void> _showDetail(Credential credential) async {
    final vaultKey = await _ensureUnlocked();
    if (vaultKey == null || !mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CredentialDetailSheet(
        credential: credential,
        vaultKey: vaultKey,
      ),
    );
  }

  Future<void> _delete(Credential credential) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete credential'),
        content: Text('Delete "${credential.siteName}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ApiService().deleteCredential(credential.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _backup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup to Google Drive'),
        content:
            const Text('Export all credentials to your Drive folder?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Backup')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await ApiService().backupToGoogleDrive();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backed up ${result['count']} credentials')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Consumer<MasterPasswordProvider>(
      builder: (context, mp, child) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            title: _searchActive
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Search credentials...',
                      border: InputBorder.none,
                    ),
                  )
                : const Text('Password Manager'),
            actions: [
              IconButton(
                icon: Icon(_searchActive ? Icons.close : Icons.search),
                tooltip: _searchActive ? 'Close search' : 'Search',
                onPressed: () {
                  setState(() {
                    _searchActive = !_searchActive;
                    if (!_searchActive) _searchController.clear();
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.backup),
                tooltip: 'Backup to Google Drive',
                onPressed: _backup,
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: () => context.push('/settings'),
              ),
            ],
          ),
          body: _buildBody(),
          floatingActionButton: FloatingActionButton(
            onPressed: () async {
              await context.push('/add');
              _load();
            },
            tooltip: 'Add credential',
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_credentials.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No credentials yet.\nTap + to add one.',
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final filtered = _filtered;
    if (filtered.isEmpty) {
      return const Center(child: Text('No results match your search.'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: filtered.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _CredentialCard(
          credential: filtered[i],
          onTap: () => _showDetail(filtered[i]),
          onEdit: () async {
            await context.push('/add', extra: filtered[i]);
            _load();
          },
          onDelete: () => _delete(filtered[i]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Credential card
// ---------------------------------------------------------------------------

class _CredentialCard extends StatelessWidget {
  final Credential credential;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CredentialCard({
    required this.credential,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            credential.siteName.isNotEmpty
                ? credential.siteName[0].toUpperCase()
                : '?',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer),
          ),
        ),
        title: Text(credential.siteName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: credential.usernameHint.isNotEmpty
            ? Text(credential.usernameHint)
            : null,
        trailing: PopupMenuButton<String>(
          onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Credential detail bottom sheet
// ---------------------------------------------------------------------------

class _CredentialDetailSheet extends StatefulWidget {
  final Credential credential;
  final Uint8List vaultKey;

  const _CredentialDetailSheet(
      {required this.credential, required this.vaultKey});

  @override
  State<_CredentialDetailSheet> createState() =>
      _CredentialDetailSheetState();
}

class _CredentialDetailSheetState extends State<_CredentialDetailSheet> {
  String? _plaintext;
  bool _decrypting = true;
  String? _error;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _decrypt();
  }

  Future<void> _decrypt() async {
    try {
      final p = CryptoService.decrypt(
        widget.credential.encryptedPayload,
        widget.credential.iv,
        widget.vaultKey,
      );
      setState(() => _plaintext = p);
    } catch (_) {
      // Decryption can fail if this credential was encrypted with a different
      // vault key (e.g. before migrating to the vault-key model).
      // The master password is still valid — do NOT clear it.
      setState(() => _error =
          'Could not decrypt this credential. It was encrypted with a '
          'different key. Delete and re-add it.');
    } finally {
      setState(() => _decrypting = false);
    }
  }

  void _copy() {
    if (_plaintext == null) return;
    Clipboard.setData(ClipboardData(text: _plaintext!));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Password copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text(widget.credential.siteName,
              style: Theme.of(context).textTheme.headlineSmall),
          if (widget.credential.usernameHint.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(widget.credential.usernameHint,
                style: const TextStyle(color: Colors.grey)),
          ],
          const SizedBox(height: 24),
          const Text('Password',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_decrypting)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    _obscure
                        ? '•' * (_plaintext?.length ?? 8)
                        : _plaintext!,
                    style: const TextStyle(
                        fontSize: 16, fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: _copy,
                  tooltip: 'Copy',
                ),
              ],
            ),
          const SizedBox(height: 16),
          Text(
            'Last updated: ${_formatDate(widget.credential.updatedAt)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
