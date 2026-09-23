// features/auth/presentation/splash_screen.dart
//
// SCREEN 1 — App splash.
//
// Authenticated (valid session):
//   Splash → restoreSession → Dashboard / existing property routing
//
// Unauthenticated (including after logout):
//   Splash → /onboarding ("Your Stay, Simplified") → Login
//
// Never skip the app intro based on AppPrefs.isFirstTime.
// Never send unauthenticated users to property "Welcome to Dormly".

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/auth_repository.dart';
import 'login_flow.dart';

const _splashPurpleTop = Color(0xFF5218D1);
const _splashPurpleBottom = Color(0xFF6D28D9);

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
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

    // Hold splash long enough to read branding, then navigate.
    await Future.delayed(const Duration(milliseconds: 2200));
    await sessionFuture;
    if (!mounted) return;

    // Authenticated: restore session → dashboard (or post-auth property welcome).
    if (hasSession) {
      try {
        await restoreSession(context, ref);
        return;
      } catch (e) {
        debugPrint('Splash session restore failed: $e');
        await authRepo.logout();
        if (!mounted) return;
      }
    }

    if (!mounted) return;

    // Unauthenticated: always show app intro before login.
    context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _splashPurpleBottom,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _splashPurpleTop,
        // Edge-to-edge: no SafeArea around the image (avoids top/bottom bars).
        body: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Full-screen splash art — cover + bottom-aligned so buildings
              // stay anchored and purple fills any leftover edges.
              Positioned.fill(
                child: Image.asset(
                  'assets/images/splash1.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomCenter,
                  excludeFromSemantics: true,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: _splashPurpleTop,
                  ),
                ),
              ),
              // Logo / tagline / loader sit above the art (safe for notches).
              SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 90,
                          height: 90,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const ColoredBox(
                              color: Color(0xFF5218D1),
                              child: Icon(
                                Icons.apartment,
                                size: 70,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Dormly',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'A better place to live, together.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFE9D5FF).withValues(alpha: 0.92),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                      ),
                    ),
                    const Spacer(flex: 3),
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Loading your space...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
