// features/auth/presentation/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // TODO: later, check for a stored token and route straight to
    // /dashboard/empty or /dashboard/:propertyId if the user is already
    // logged in. For now, always send to login so we can see the flow.
    Future.delayed(const Duration(milliseconds: 800), () {
     if (mounted) context.go('/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}