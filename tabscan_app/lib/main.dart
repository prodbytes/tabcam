import 'package:flutter/material.dart';

import 'app_version.dart';
import 'library/library.dart';
import 'screens/library_screen.dart';

void main() {
  runApp(TabScanApp(library: Library()..load()));
}

class TabScanApp extends StatelessWidget {
  const TabScanApp({super.key, required this.library});

  final Library library;

  @override
  Widget build(BuildContext context) {
    // Amber, like a maple fretboard; dark by default for dim rehearsal rooms.
    ThemeData theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFE0A030),
        brightness: brightness,
      ),
    );
    return MaterialApp(
      title: AppVersion.title,
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: LibraryScreen(library: library),
    );
  }
}
