// main.dart
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';

void main() async {
  // Must be the very first call — required before any plugin or binding access.
  WidgetsFlutterBinding.ensureInitialized();

  // Prevent google_fonts from making live HTTP calls to fonts.googleapis.com
  // in release builds. Falls back to system fonts if not already cached —
  // avoids a network timeout stalling the very first theme build.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Catch Flutter framework errors (widget build failures, rendering errors).
  // In release mode these are otherwise silent white-screens.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  // Catch all other async / platform-channel errors that escape the zone.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('PlatformDispatcher error: $error\n$stack');
    return true; // returning true prevents the app from being killed
  };

  // Initialize AdMob — wrapped so a native init failure never crashes startup.
  try {
    await MobileAds.instance.initialize();
  } catch (e) {
    debugPrint('AdMob init failed (non-fatal): $e');
  }

  runApp(const ProviderScope(child: DormlyApp()));
}

class DormlyApp extends StatelessWidget {
  const DormlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Dormly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
    );
  }
}
