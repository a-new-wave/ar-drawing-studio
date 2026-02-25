import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/onboarding_screen.dart';
import 'screens/workspace_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isFirstLaunch = prefs.getBool('is_first_launch') ?? true;

  runApp(
    ProviderScope(
      child: ARDrawingStudio(isFirstLaunch: isFirstLaunch),
    ),
  );
}

class ARDrawingStudio extends StatelessWidget {
  final bool isFirstLaunch;
  const ARDrawingStudio({super.key, required this.isFirstLaunch});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AR Drawing Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: isFirstLaunch ? const OnboardingScreen() : const WorkspaceScreen(),
    );
  }
}
