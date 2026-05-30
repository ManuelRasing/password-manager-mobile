import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/credential.dart';
import '../providers/master_password_provider.dart';
import '../services/api_service.dart';
import '../services/password_health_service.dart';
import '../widgets/master_password_dialog.dart';

class PasswordHealthScreen extends StatefulWidget {
  const PasswordHealthScreen({super.key});

  @override
  State<PasswordHealthScreen> createState() => _PasswordHealthScreenState();
}

class _PasswordHealthScreenState extends State<PasswordHealthScreen> {
  bool _loading = true;
  String? _error;
  HealthReport? _report;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<Uint8List?> _ensureUnlocked() async {
    final mp = context.read<MasterPasswordProvider>();
    if (mp.isUnlocked) return mp.vaultKey;
    if (!mounted) return null;
    final vaultKey = await showMasterPasswordDialog(context);
    if (vaultKey != null && mounted) mp.set(vaultKey);
    return vaultKey;
  }

  Future<void> _run() async {
    setState(() { _loading = true; _error = null; });
    try {
      final vaultKey = await _ensureUnlocked();
      if (vaultKey == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final credentials = await ApiService().getCredentials();
      final report =
          await PasswordHealthService.analyze(credentials, vaultKey);
      if (mounted) setState(() => _report = report);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editCredential(Credential c) async {
    await context.push('/add', extra: c);
    if (mounted) _run(); // re-analyse after a possible edit
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Password Health'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-scan',
            onPressed: _loading ? null : _run,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Analysing your passwords…'),
            SizedBox(height: 4),
            Text('Checking against known breaches (HIBP)',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
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
              FilledButton(onPressed: _run, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final report = _report;
    if (report == null || report.items.isEmpty) {
      return const Center(child: Text('No credentials to analyse.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ScoreCard(report: report),
        const SizedBox(height: 16),
        if (!report.breachCheckAvailable)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Breach check was unavailable (offline). Weak and reused checks '
              'still ran.',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
        _IssueSection(
          title: 'Breached',
          subtitle: 'Found in known data breaches — change these first',
          icon: Icons.warning_amber_rounded,
          color: Colors.red,
          items: report.breached,
          trailingFor: (h) => '${h.breachCount} breaches',
          onTap: _editCredential,
        ),
        _IssueSection(
          title: 'Reused',
          subtitle: 'The same password is used on multiple sites',
          icon: Icons.copy_all,
          color: Colors.orange,
          items: report.reused,
          onTap: _editCredential,
        ),
        _IssueSection(
          title: 'Weak',
          subtitle: 'Short or low-complexity passwords',
          icon: Icons.lock_open,
          color: Colors.amber,
          items: report.weak,
          onTap: _editCredential,
        ),
        if (report.items.every((i) => !i.hasIssue))
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                Icon(Icons.verified_user, size: 56, color: Colors.green),
                SizedBox(height: 12),
                Text('All your passwords look healthy 🎉',
                    textAlign: TextAlign.center),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Score card ──────────────────────────────────────────────────────────────
class _ScoreCard extends StatelessWidget {
  final HealthReport report;
  const _ScoreCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final score = report.score;
    final color = score >= 80
        ? Colors.green
        : score >= 50
            ? Colors.orange
            : Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: score / 100,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                    strokeWidth: 6,
                  ),
                  Text('$score',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: color)),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Vault Health',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    '${report.items.length} credentials · '
                    '${report.breached.length} breached · '
                    '${report.reused.length} reused · '
                    '${report.weak.length} weak',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Issue section ───────────────────────────────────────────────────────────
class _IssueSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<CredentialHealth> items;
  final String Function(CredentialHealth)? trailingFor;
  final void Function(Credential) onTap;

  const _IssueSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.items,
    required this.onTap,
    this.trailingFor,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text('$title (${items.length})',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        children: items.map((h) {
          return ListTile(
            dense: true,
            title: Text(h.credential.siteName),
            subtitle: h.credential.usernameHint.isNotEmpty
                ? Text(h.credential.usernameHint)
                : null,
            trailing: trailingFor != null
                ? Text(trailingFor!(h),
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600))
                : const Icon(Icons.chevron_right, size: 18),
            onTap: () => onTap(h.credential),
          );
        }).toList(),
      ),
    );
  }
}
