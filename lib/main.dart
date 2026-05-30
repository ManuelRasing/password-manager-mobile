import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/add_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/change_master_password_screen.dart';
import 'screens/password_health_screen.dart';
import 'services/storage_service.dart';
import 'providers/master_password_provider.dart';
import 'models/credential.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Screenshot blocking is set natively in MainActivity.kt (Android) — see
  // FLAG_SECURE in onCreate. iOS blurs the app automatically on background.

  final isConfigured = await StorageService.isConfigured();
  final isVaultSetup = await StorageService.isVaultSetup();

  // Routing priority:
  //   1. Not configured (no API key / server URL) → Settings
  //   2. Configured but vault not set up locally  → Setup
  //      (SetupScreen will detect server-side vault for new-device unlock)
  //   3. Fully ready                              → Home
  final String initialLocation;
  if (!isConfigured) {
    initialLocation = '/settings';
  } else if (!isVaultSetup) {
    initialLocation = '/setup';
  } else {
    initialLocation = '/';
  }

  runApp(PasswordManagerApp(initialLocation: initialLocation));
}

class PasswordManagerApp extends StatefulWidget {
  final String initialLocation;

  const PasswordManagerApp({super.key, required this.initialLocation});

  @override
  State<PasswordManagerApp> createState() => _PasswordManagerAppState();
}

class _PasswordManagerAppState extends State<PasswordManagerApp> {
  // Auto-lock: clear vault key after 5 minutes of inactivity.
  static const _lockTimeout = Duration(minutes: 5);
  Timer? _inactivityTimer;

  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: widget.initialLocation,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/setup',
          builder: (context, state) => const SetupScreen(),
        ),
        GoRoute(
          path: '/add',
          builder: (context, state) => AddScreen(
            credential: state.extra as Credential?,
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/change-password',
          builder: (context, state) => const ChangeMasterPasswordScreen(),
        ),
        GoRoute(
          path: '/password-health',
          builder: (context, state) => const PasswordHealthScreen(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _resetInactivityTimer(BuildContext ctx) {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_lockTimeout, () {
      // Clear vault key on idle — next vault operation will re-prompt
      ctx.read<MasterPasswordProvider>().clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MasterPasswordProvider(),
      child: Builder(
        builder: (ctx) => Listener(
          // Any pointer event resets the inactivity timer
          onPointerDown: (_) => _resetInactivityTimer(ctx),
          child: MaterialApp.router(
            title: 'Password Manager',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
              useMaterial3: true,
            ),
            routerConfig: _router,
          ),
        ),
      ),
    );
  }
}
