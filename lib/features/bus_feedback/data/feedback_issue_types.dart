import 'dart:convert';

/// Keeps historical plain strings and multiple selections in the text column.
List<String> decodeFeedbackIssueTypes(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is List && decoded.every((item) => item is String)) {
      return List.unmodifiable(
        decoded.cast<String>().where((s) => s.trim().isNotEmpty).toSet(),
      );
    }
  } on FormatException {
    // Historical issue labels are plain text.
  }
  return value.trim().isEmpty ? const [] : [value];
}

String encodeFeedbackIssueTypes(Iterable<String> issues) {
  final values = issues.where((s) => s.trim().isNotEmpty).toSet().toList();
  return values.length == 1 ? values.single : jsonEncode(values);
}
