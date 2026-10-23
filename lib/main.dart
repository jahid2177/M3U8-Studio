import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'ui/studio_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const StudioApp());
}
