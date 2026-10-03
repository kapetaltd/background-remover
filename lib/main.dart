import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts ship in assets/google_fonts, so the app works offline and makes no
  // network requests.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const CutoutApp());
}
