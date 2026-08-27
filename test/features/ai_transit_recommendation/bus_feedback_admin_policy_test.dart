import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds an admin-only select policy for bus feedback', () {
    final sql = File(
      'supabase/migrations/20260827000000_bus_feedback_admin_read.sql',
    ).readAsStringSync();
    final normalized = sql.toLowerCase();

    expect(normalized, contains('on public.bus_feedback for select'));
    expect(normalized, contains('to authenticated'));
    expect(normalized, contains('using (public.is_admin())'));
    expect(normalized, isNot(contains('for insert')));
    expect(normalized, isNot(contains('for update')));
    expect(normalized, isNot(contains('for delete')));
  });
}
