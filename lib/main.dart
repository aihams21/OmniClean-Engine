import 'package:flutter/material.dart';

import 'bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await prepareWindow();
  final runtime = await bootstrapRuntime();
  runApp(OmniCleanApp(runtime: runtime));
}
