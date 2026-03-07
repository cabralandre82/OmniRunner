import 'dart:convert';

import 'package:drift/drift.dart';

/// Converts [List<String>] to/from a JSON-encoded [String] for Drift TEXT columns.
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return [];
    final decoded = jsonDecode(fromDb);
    if (decoded is List) return decoded.map((e) => e.toString()).toList();
    return [];
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}
