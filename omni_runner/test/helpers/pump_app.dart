import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_runner/l10n/app_localizations.dart';

extension PumpApp on WidgetTester {
  Future<void> pumpApp(Widget widget, {ThemeData? theme, bool wrapScaffold = true}) async {
    await pumpWidget(
      MaterialApp(
        theme: theme ?? ThemeData.light(useMaterial3: true),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('pt'),
        home: wrapScaffold ? Scaffold(body: widget) : widget,
      ),
    );
    await pump();
  }
}
