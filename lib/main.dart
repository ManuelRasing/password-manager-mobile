import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/add_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/change_master_password_screen.dart';
import 'services/storage_service.dart';
import 'providers/master_password_provider.dart';
import 'models/credential.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

class PasswordManagerApp extends StatelessWidget {
  final String initialLocation;

  const PasswordManagerApp({super.key, required this.initialLocation});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: initialLocation,
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
      ],
    );

    return ChangeNotifierProvider(
      create: (_) => MasterPasswordProvider(),
      child: MaterialApp.router(
        title: 'Password Manager',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        routerConfig: router,
      ),
    );
  }
}
