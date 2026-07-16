// core/widgets/property_illustration.dart
//
// A simple illustrated composition built from icons only (no external
// image assets needed) — a building flanked by trees, in brand colors.
// Used for empty states so they feel warm rather than blank.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PropertyIllustration extends StatelessWidget {
  final double size;
  const PropertyIllustration({super.key, this.size = 160});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.blueprint.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
          ),
          Positioned(
            left: size * 0.08,
            bottom: size * 0.18,
            child: Icon(Icons.park, size: size * 0.22, color: AppColors.positive.withOpacity(0.5)),
          ),
          Positioned(
            right: size * 0.08,
            bottom: size * 0.22,
            child: Icon(Icons.park, size: size * 0.18, color: AppColors.positive.withOpacity(0.4)),
          ),
          Icon(Icons.apartment_rounded, size: size * 0.5, color: AppColors.blueprint),
        ],
      ),
    );
  }
}