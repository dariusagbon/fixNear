import 'package:flutter/material.dart';

import 'core/services/firebase_initializer.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_gate.dart';

class FixNearApp extends StatelessWidget {
  const FixNearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FixNear',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AppInitializationGate(),
    );
  }
}

class AppInitializationGate extends StatefulWidget {
  const AppInitializationGate({super.key});

  @override
  State<AppInitializationGate> createState() => _AppInitializationGateState();
}

class _AppInitializationGateState extends State<AppInitializationGate> {
  bool _isReady = false;
  Object? _initializationError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await FirebaseInitializer.ensureInitialized();
      if (!mounted) return;
      setState(() {
        _initializationError = null;
        _isReady = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _initializationError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializationError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Firebase could not be initialized.'),
                const SizedBox(height: 8),
                Text(
                  'Check the Firebase configuration for this platform.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    setState(() => _isReady = false);
                    _init();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return const AuthGate();
  }
}
