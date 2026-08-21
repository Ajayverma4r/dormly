// features/subscription/presentation/widgets/ad_banner_gate.dart
//
// Shows a Google AdMob banner when the org is on Free tier (ads_enabled),
// including free residential (Rental/House/Villa) and free commercial/apartment.
// Paid Pro/Enterprise subscriptions always hide ads.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../properties/domain/property_monetization.dart';
import '../subscription_provider.dart';

const _kAndroidBannerUnitId = 'ca-app-pub-3940256099942544/6300978111';
const _kIosBannerUnitId = 'ca-app-pub-3940256099942544/2934735716';

class AdBannerGate extends ConsumerStatefulWidget {
  /// Optional active property type — free residential types force ads on free tier.
  final String? propertyTypeKey;

  const AdBannerGate({super.key, this.propertyTypeKey});

  @override
  ConsumerState<AdBannerGate> createState() => _AdBannerGateState();
}

class _AdBannerGateState extends ConsumerState<AdBannerGate> {
  BannerAd? _ad;
  bool _loaded = false;

  bool _shouldShowAds(WidgetRef ref) {
    final sub = ref.watch(subscriptionProvider).valueOrNull;
    final isPaid = PropertyMonetization.isPaidPlan(
      sub?.subscription.planSlug,
      sub?.subscription.status,
    );
    if (isPaid) return false;

    final adsEnabled = ref.watch(canProvider('ads_enabled'));
    final freeType =
        PropertyMonetization.isFreeResidential(widget.propertyTypeKey);
    return adsEnabled || freeType;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAdIfNeeded();
  }

  @override
  void didUpdateWidget(covariant AdBannerGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.propertyTypeKey != widget.propertyTypeKey) {
      _ad?.dispose();
      _ad = null;
      _loaded = false;
      _loadAdIfNeeded();
    }
  }

  void _loadAdIfNeeded() {
    if (!_shouldShowAds(ref) || _ad != null) return;

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
    final show = _shouldShowAds(ref);
    if (!show) {
      if (_ad != null) {
        _ad!.dispose();
        _ad = null;
        _loaded = false;
      }
      return const SizedBox.shrink();
    }

    if (_ad == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadAdIfNeeded();
      });
      return const SizedBox.shrink();
    }

    if (!_loaded) return const SizedBox.shrink();

    return SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
