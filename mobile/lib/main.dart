// main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';

void main() {
  // Binding must be initialized before any plugin calls (AdMob, secure storage, etc.)
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize AdMob SDK early — AdBannerGate handles load failures gracefully
  // if the SDK isn't ready yet, so we don't need to await this.
  MobileAds.instance.initialize();
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
