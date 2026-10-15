// The default `flutter create` counter test referred to a `MyApp` counter app
// that Dormly never had. This keeps a check that the real entry widget builds
// against the current API without starting the router, storage or ads.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dormly/main.dart';

void main() {
  test('DormlyApp is the app entry widget', () {
    expect(const DormlyApp(), isA<StatelessWidget>());
  });
}
