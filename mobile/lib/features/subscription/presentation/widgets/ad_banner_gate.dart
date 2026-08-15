// features/subscription/presentation/widgets/ad_banner_gate.dart
//
// Renders a Google AdMob banner ONLY when ads_enabled == true in the org's
// active entitlements. Pro/Enterprise plans have ads_enabled = false → the
// banner never mounts for paid users, giving them an ad-free experience.
//
// ── Native setup required ────────────────────────────────────────────────────
//
// Android  android/app/src/main/AndroidManifest.xml  (inside <application>):
//   <meta-data
//     android:name="com.google.android.gms.ads.APPLICATION_ID"
//     android:value="ca-app-pub-xxxxxxxxxxxxxxxx~yyyyyyyyyy"/>
//
// iOS  ios/Runner/Info.plist:
//   <key>GADApplicationIdentifier</key>
//   <string>ca-app-pub-xxxxxxxxxxxxxxxx~yyyyyyyyyy</string>
//
// Replace the placeholder IDs above with your real AdMob app IDs.
// The test banner unit IDs below are safe to use during development.
//
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../subscription_provider.dart';

/// AdMob unit IDs — swap for real IDs before publishing to store.
const _kAndroidBannerUnitId = 'ca-app-pub-3940256099942544/6300978111'; // Google test ID
const _kIosBannerUnitId     = 'ca-app-pub-3940256099942544/2934735716'; // Google test ID

class AdBannerGate extends ConsumerStatefulWidget {
  const AdBannerGate({super.key});

  @override
  ConsumerState<AdBannerGate> createState() => _AdBannerGateState();
}

class _AdBannerGateState extends ConsumerState<AdBannerGate> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAdIfNeeded();
  }

  void _loadAdIfNeeded() {
    // Only load if ads_enabled is true (determined by subscription entitlement)
    final adsEnabled = ref.read(canProvider('ads_enabled'));
    if (!adsEnabled || _ad != null) return;

    _ad = BannerAd(
      adUnitId: Platform.isIOS ? _kIosBannerUnitId : _kAndroidBannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-check on every rebuild in case subscription refreshes
    final adsEnabled = ref.watch(canProvider('ads_enabled'));
    if (!adsEnabled || _ad == null || !_loaded) return const SizedBox.shrink();

    return SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
