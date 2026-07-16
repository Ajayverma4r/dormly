// core/widgets/blueprint_grid_painter.dart
//
// Dormly's one signature visual motif: a faint architectural graph-paper
// grid, used ONLY behind the hero revenue figure on the analytics screen.
// Everything else in the UI stays deliberately quiet.

import 'package:flutter/material.dart';

class BlueprintGridPainter extends CustomPainter {
  final Color lineColor;
  const BlueprintGridPainter({this.lineColor = const Color(0x142451B4)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    const step = 14.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}