import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bottom sheet for generating strong random passwords.
/// Call [showPasswordGeneratorSheet] and await the result —
/// returns the chosen password string, or null if dismissed.
Future<String?> showPasswordGeneratorSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _PasswordGeneratorSheet(),
  );
}

class _PasswordGeneratorSheet extends StatefulWidget {
  const _PasswordGeneratorSheet();

  @override
  State<_PasswordGeneratorSheet> createState() =>
      _PasswordGeneratorSheetState();
}

class _PasswordGeneratorSheetState extends State<_PasswordGeneratorSheet> {
  int _length = 16;
  bool _uppercase = true;
  bool _lowercase = true;
  bool _numbers = true;
  bool _symbols = true;
  String _generated = '';

  static const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const _digits = '0123456789';
  static const _syms = '!@#\$%^&*()_+-=[]{}|;:,.<>?';

  @override
  void initState() {
    super.initState();
    _generate();
  }

  void _generate() {
    String chars = '';
    if (_uppercase) chars += _upper;
    if (_lowercase) chars += _lower;
    if (_numbers) chars += _digits;
    if (_symbols) chars += _syms;
    if (chars.isEmpty) chars = _lower; // fallback — always produce something

    final rng = Random.secure();
    setState(() {
      _generated =
          List.generate(_length, (_) => chars[rng.nextInt(chars.length)])
              .join();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
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
          Text('Password Generator',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),

          // Generated password display
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _generated,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 15,
                        letterSpacing: 1),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Regenerate',
                  onPressed: _generate,
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _generated));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Length slider
          Row(
            children: [
              const Text('Length'),
              Expanded(
                child: Slider(
                  value: _length.toDouble(),
                  min: 8,
                  max: 32,
                  divisions: 24,
                  label: '$_length',
                  onChanged: (v) {
                    setState(() => _length = v.round());
                    _generate();
                  },
                ),
              ),
              Text('$_length',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),

          // Character set toggles
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('A–Z'),
                selected: _uppercase,
                onSelected: (v) {
                  setState(() => _uppercase = v);
                  _generate();
                },
              ),
              FilterChip(
                label: const Text('a–z'),
                selected: _lowercase,
                onSelected: (v) {
                  setState(() => _lowercase = v);
                  _generate();
                },
              ),
              FilterChip(
                label: const Text('0–9'),
                selected: _numbers,
                onSelected: (v) {
                  setState(() => _numbers = v);
                  _generate();
                },
              ),
              FilterChip(
                label: const Text('!@#'),
                selected: _symbols,
                onSelected: (v) {
                  setState(() => _symbols = v);
                  _generate();
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          FilledButton(
            onPressed: () => Navigator.pop(context, _generated),
            child: const Text('Use this password'),
          ),
        ],
      ),
    );
  }
}
