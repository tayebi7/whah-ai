import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'chat_page.dart';
import 'theme.dart';

/// system | light | dark — يتغير فوراً من الإعدادات
final ValueNotifier<String> themeModeNotifier = ValueNotifier<String>('system');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WahaAI());
}

class WahaAI extends StatelessWidget {
  const WahaAI({super.key});

  ThemeMode _mode(String m) {
    switch (m) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'WHAH AI',
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.build(Brightness.light),
        darkTheme: AppTheme.build(Brightness.dark),
        themeMode: _mode(mode),
        home: const ChatPage(),
      ),
    );
  }
}
