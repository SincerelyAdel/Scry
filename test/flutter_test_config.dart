import 'dart:async';

import 'package:scry/widgets/veins.dart';

/// Veined text stays still in tests, so screens settle.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  DriftClock.enabled = false;
  await testMain();
}
