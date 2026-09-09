import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const migrationPath =
    'supabase/migrations/20260910000000_saved_operational_reports.sql';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(migrationPath).readAsStringSync().toLowerCase();
  });

  test('creates dedicated operational report types and table constraints', () {
    expect(sql, contains('create type public.saved_operational_report_type'));
    expect(sql, contains("'route_performance'"));
    expect(sql, contains("'peak_operation'"));
    expect(sql, contains('create type public.saved_operational_report_status'));
    expect(sql, contains("'draft'"));
    expect(sql, contains("'reviewed'"));
    expect(sql, contains("'needs_attention'"));
    expect(sql, contains("'resolved'"));
    expect(sql, contains('create table public.saved_operational_reports'));
    expect(sql, contains('result_snapshot jsonb not null'));
    expect(sql, contains("jsonb_typeof(result_snapshot) = 'object'"));
    expect(sql, contains('period_end > period_start'));
    expect(
      sql,
      contains(
        "new.report_type =\n          'route_performance'::public.saved_operational_report_type",
      ),
    );
    expect(sql, isNot(contains('unique (')));
  });

  test('preserves route history and permits a network-wide peak scope', () {
    expect(
      sql,
      contains(
        'route_id text references public.gtfs_routes(route_id) on delete set null',
      ),
    );
    expect(sql, isNot(contains('route_id text not null')));
    expect(sql, contains('route_name_snapshot text not null'));
    expect(sql, contains('and new.route_id is null'));
    expect(
      sql,
      contains('before insert or update on public.saved_operational_reports'),
    );
  });

  test('protects snapshot columns while leaving management fields editable', () {
    final guard = sql.substring(
      sql.indexOf(
        'create or replace function public.protect_saved_operational_report_snapshot()',
      ),
      sql.indexOf(
        'comment on function public.protect_saved_operational_report_snapshot()',
      ),
    );
    for (final column in [
      'report_id',
      'admin_id',
      'report_type',
      'route_name_snapshot',
      'period_start',
      'period_end',
      'result_snapshot',
      'created_at',
    ]) {
      expect(guard, contains('new.$column is distinct from old.$column'));
    }
    expect(guard, contains('new.route_id is distinct from old.route_id'));
    expect(guard, contains('not exists'));
    expect(guard, isNot(contains('new.title is distinct')));
    expect(guard, isNot(contains('new.admin_notes is distinct')));
    expect(guard, isNot(contains('new.status is distinct')));
    expect(sql, contains('execute function public.set_updated_at()'));
  });

  test('enables shared-admin CRUD RLS and prevents creator spoofing', () {
    expect(
      sql,
      contains(
        'alter table public.saved_operational_reports enable row level security',
      ),
    );
    for (final operation in ['select', 'insert', 'update', 'delete']) {
      expect(
        sql,
        contains('on public.saved_operational_reports for $operation'),
      );
    }
    expect(sql, contains('using (public.is_admin())'));
    expect(
      sql,
      contains('with check (public.is_admin() and admin_id = auth.uid())'),
    );
    expect(sql, contains('to authenticated'));
  });

  test('adds practical indexes without touching generic analysis tables', () {
    expect(sql, contains('(report_type, created_at desc)'));
    expect(sql, contains('(status, created_at desc)'));
    expect(sql, contains('(route_id, created_at desc)'));
    expect(sql, contains('(admin_id, created_at desc)'));
    expect(sql, isNot(contains('alter table public.analysis_reports')));
    expect(sql, isNot(contains('alter table public.ai_recommendations')));
  });
}
