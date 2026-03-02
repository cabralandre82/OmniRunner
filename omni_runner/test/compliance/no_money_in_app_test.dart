import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// CI compliance gate: ensures NO monetary terms appear in user-visible
/// Dart code under lib/presentation/ (screens, widgets, blocs).
///
/// Allowed contexts (false positives):
///   - "Taxa de vitória" / "taxa de participação" → sports rate, not fee
///   - "Valor" as a metric label (pace, distance) → not money
///   - Variable names like `entryFeeCoins`, `_feeCtrl` → internal, not shown as "$"
///   - "feed" (activity feed, assessoria feed) → not financial
///
/// Prohibited patterns checked:
///   R$, €, US$, USD, BRL, dinheiro, preço/preco, pagamento, pagar,
///   saque, resgate, withdraw, cash, money, cobrança/cobranca
void main() {
  test('COMPLIANCE: no monetary terms in app presentation layer', () {
    final dir = Directory('lib/presentation');
    if (!dir.existsSync()) {
      fail('lib/presentation directory not found');
    }

    // Hard-banned patterns: these should NEVER appear in UI code.
    final prohibited = RegExp(
      r'''R\$|€|US\$'''
      r'''|\bUSD\b|\bBRL\b'''
      r'''|\bdinheiro\b|\bpreço\b|\bpreco\b'''
      r'''|\bpagamento\b|\bpagar\b'''
      r'''|\bsaque\b|\bresgate\b'''
      r'''|\bwithdraw\b|\bcash\b|\bmoney\b'''
      r'''|\bcobrança\b|\bcobranca\b''',
      caseSensitive: false,
    );

    final violations = <String>[];

    for (final file in dir.listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Skip import lines, comments-only lines
        if (line.trimLeft().startsWith('import ')) continue;
        if (line.trimLeft().startsWith('//')) continue;

        if (prohibited.hasMatch(line)) {
          violations.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Found ${violations.length} monetary term(s) in app UI:\n'
        '${violations.join('\n')}',
      );
    }
  });

  test('COMPLIANCE: no monetary terms in analytics/tracking code', () {
    final dirs = [
      Directory('lib/core/analytics'),
      Directory('lib/data/datasources'),
    ];

    final prohibited = RegExp(
      r'''\busd\b|\bbrl\b|\bprice\b|\bmoney\b|\bcash\b|\bpayment\b|\bvalor\b|\bdinheiro\b''',
      caseSensitive: false,
    );

    final violations = <String>[];

    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('import ')) continue;
          if (line.trimLeft().startsWith('//')) continue;
          if (prohibited.hasMatch(line)) {
            violations.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Found ${violations.length} monetary term(s) in analytics:\n'
        '${violations.join('\n')}',
      );
    }
  });
}
