// core/widgets/step_indicator.dart
//
// Numbered step indicator (①—②—③) with connecting lines, matching a
// proper multi-step wizard rather than plain "Step X of 3" text.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StepIndicator extends StatelessWidget {
  final int currentStep; // 0-indexed
  final List<String> labels;

  const StepIndicator({super.key, required this.currentStep, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length * 2 - 1, (i) {
        if (i.isOdd) {
          final leftStep = i ~/ 2;
          final isDone = leftStep < currentStep;
          return Expanded(
            child: Container(height: 2, color: isDone ? AppColors.blueprint : AppColors.hairline),
          );
        }
        final step = i ~/ 2;
        final isDone = step < currentStep;
        final isActive = step == currentStep;
        final circleColor = isDone || isActive ? AppColors.blueprint : AppColors.hairline;
        return Column(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? AppColors.blueprint : Colors.transparent,
                border: Border.all(color: circleColor, width: 2),
              ),
              alignment: Alignment.center,
              child: isDone
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text(
                      '${step + 1}',
                      style: TextStyle(
                        color: isActive ? AppColors.blueprint : AppColors.slate,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              labels[step],
              style: TextStyle(
                fontSize: 11,
                color: isActive ? AppColors.ink : AppColors.slate,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        );
      }),
    );
  }
}