// features/auth/presentation/splash_screen.dart
//
// Premium splash: full-screen login_bg.png, staggered logo + tagline fade,
// then session restore or login.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/auth_repository.dart';
import 'login_flow.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  // Start visible so Android 12+ system splash (logo on blue) does not blink
  // off when the Flutter splash takes over.
  bool _showLogo = true;
  bool _showTagline = false;

  @override
  void initState() {
    super.initState();
    _runSequence();
  }

  Future<void> _runSequence() async {
    final authRepo = ref.read(authRepositoryProvider);
    var hasSession = false;

    final sessionFuture = authRepo.hasPersistedSession().then((v) {
      hasSession = v;
    }).catchError((Object e) {
      debugPrint('Splash session read failed (non-fatal): $e');
    });

    // Logo is already visible (matches Android 12 native splash icon).
    // Tagline fades in at ~1200ms.
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _showTagline = true);

    // Navigate at ~3000ms total.
    await Future.delayed(const Duration(milliseconds: 1800));
    await sessionFuture;
    if (!mounted) return;

    if (hasSession) {
      try {
        await restoreSession(context, ref);
        return;
      } catch (e) {
        debugPrint('Splash session restore failed: $e');
        await authRepo.logout();
        if (mounted) context.go('/login');
        return;
      }
    }

    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      // Opaque blue matches login_bg so there is no gray theme flash
      // while the background image decodes (native splash already shows it).
      child: Scaffold(
        backgroundColor: const Color(0xFF0127C6),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/login_bg.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedOpacity(
                    opacity: _showLogo ? 1 : 0,
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    child: Column(
                      children: [
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Dormly',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedOpacity(
                    opacity: _showTagline ? 1 : 0,
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    child: Text(
                      'One property. Every property.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
