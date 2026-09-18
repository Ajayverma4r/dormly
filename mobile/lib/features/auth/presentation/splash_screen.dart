// features/auth/presentation/splash_screen.dart
//
// Primary first frame (Picture 2): purple gradient, logo, tagline, splash1
// buildings, loader. Native Android launch is solid purple only (no circular
// logo placeholder) so this screen appears as soon as Flutter paints.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/storage/app_prefs.dart';
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
    var firstTime = true;

    final sessionFuture = authRepo.hasPersistedSession().then((v) {
      hasSession = v;
    }).catchError((Object e) {
      debugPrint('Splash session read failed (non-fatal): $e');
    });

    final firstTimeFuture = AppPrefs.isFirstTime().then((v) {
      firstTime = v;
    }).catchError((Object e) {
      debugPrint('Splash first-time read failed (non-fatal): $e');
      firstTime = true;
    });

    // Hold Picture 2 long enough to read branding, then navigate.
    await Future.delayed(const Duration(milliseconds: 2200));
    await Future.wait([sessionFuture, firstTimeFuture]);
    if (!mounted) return;

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

    if (firstTime) {
      context.go('/onboarding');
    } else {
      context.go('/login');
    }
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
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_splashPurpleTop, _splashPurpleBottom],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Bottom building illustration (splash1).
              Align(
                alignment: Alignment.bottomCenter,
                child: Image.asset(
                  'assets/images/splash1.png',
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.bottomCenter,
                  excludeFromSemantics: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
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
