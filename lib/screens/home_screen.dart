import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/credential.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Credential> _credentials = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final credentials = await ApiService().getCredentials();
      setState(() => _credentials = credentials);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
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
    if (confirmed != true) return;
    try {
      await ApiService().deleteCredential(credential.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Password Manager'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
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
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _credentials.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _CredentialCard(
          credential: _credentials[i],
          onEdit: () async {
            await context.push('/add', extra: _credentials[i]);
            _load();
          },
          onDelete: () => _delete(_credentials[i]),
        ),
      ),
    );
  }

  Future<void> _backup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup to Google Drive'),
        content: const Text('Export all credentials to your Drive folder?'),
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
        SnackBar(content: Text('Backed up ${result['count']} credentials')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup failed: $e')),
      );
    }
  }
}

class _CredentialCard extends StatelessWidget {
  final Credential credential;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CredentialCard({
    required this.credential,
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
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}
