import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/favourite_stop_repository.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:government_transit_collector/features/departure_recommendation/data/departure_stop_repository.dart';
import 'package:government_transit_collector/features/departure_recommendation/presentation/stop_selection_page.dart';

class FakeStopRepository implements DepartureStopRepository {
  @override
  Future<DepartureStop?> getStopById(String id) async => null;
  FakeStopRepository(this.onSearch);

  final Future<List<DepartureStop>> Function(String query) onSearch;
  final List<String> queries = [];

  @override
  Future<List<DepartureStop>> searchStops(String query) {
    queries.add(query);
    return onSearch(query);
  }
}

Widget app(DepartureStopRepository repository, {String? excludedStopId}) =>
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: StopSelectionPage(
        title: 'Select origin',
        repository: repository,
        excludedStopId: excludedStopId,
      ),
    );

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const Key('stop-search-field')), query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

class PendingFavouriteStop extends FakeStopRepository {
  PendingFavouriteStop() : super((_) async => []);
  final pending = Completer<DepartureStop?>();
  @override
  Future<DepartureStop?> getStopById(String id) => pending.future;
}

class SavedFavourite extends FavouriteStopRepository {
  SavedFavourite() : super(userId: 'review-test', factory: databaseFactoryFfi);
  @override
  Future<List<DepartureStop>> load() async => const [
    DepartureStop(id: 'stop', name: 'Saved Stop'),
  ];
}

void main() {
  testWidgets(
    'review: pending favourite lookup cannot pop the parent after Back',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final stops = PendingFavouriteStop();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Home')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Parent Plan')),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.push(
        MaterialPageRoute<DepartureStop>(
          builder: (_) => StopSelectionPage(
            title: 'Select origin stop',
            excludedStopId: null,
            repository: stops,
            favouriteStopRepository: SavedFavourite(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use as Origin'));
      await tester.pump();
      navigator.currentState!.pop();
      stops.pending.complete(
        const DepartureStop(id: 'stop', name: 'Saved Stop'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Parent Plan'), findsOneWidget);
      expect(navigator.currentState!.canPop(), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty selector asks passenger to search without loading stops', (
    tester,
  ) async {
    final repository = FakeStopRepository((_) async => const []);
    await tester.pumpWidget(app(repository));

    expect(find.text('Search stops'), findsOneWidget);
    expect(
      find.text('Type a stop name to search all available stops'),
      findsOneWidget,
    );
    expect(find.text('Search to find a bus stop'), findsOneWidget);
    expect(repository.queries, isEmpty);
  });

  testWidgets('typed partial query can return a stop outside initial 50', (
    tester,
  ) async {
    const lateStop = DepartureStop(id: 'late-987', name: 'ZY Motorsport');
    final repository = FakeStopRepository((query) async {
      return query.toLowerCase().contains('zy') ? const [lateStop] : const [];
    });
    await tester.pumpWidget(app(repository));

    await search(tester, 'zY motor');

    expect(repository.queries, ['zY motor']);
    expect(find.text('ZY Motorsport'), findsOneWidget);
    expect(find.byKey(const Key('stop-late-987')), findsOneWidget);
  });

  testWidgets('duplicate names retain distinct stop IDs', (tester) async {
    final repository = FakeStopRepository(
      (_) async => const [
        DepartureStop(id: 'platform-a', name: 'Example Terminal'),
        DepartureStop(id: 'platform-b', name: 'Example Terminal'),
      ],
    );
    await tester.pumpWidget(app(repository));

    await search(tester, 'example');

    expect(find.text('Example Terminal'), findsNWidgets(2));
    expect(find.byKey(const Key('stop-platform-a')), findsOneWidget);
    expect(find.byKey(const Key('stop-platform-b')), findsOneWidget);
  });

  testWidgets('opposite selected stop is disabled by exact stop ID', (
    tester,
  ) async {
    final repository = FakeStopRepository(
      (_) async => const [
        DepartureStop(id: 'same-id', name: 'Shared Name'),
        DepartureStop(id: 'other-id', name: 'Shared Name'),
      ],
    );
    await tester.pumpWidget(app(repository, excludedStopId: 'same-id'));
    await search(tester, 'shared');

    final excluded = tester.widget<ListTile>(
      find.byKey(const Key('stop-same-id')),
    );
    final available = tester.widget<ListTile>(
      find.byKey(const Key('stop-other-id')),
    );
    expect(excluded.enabled, isFalse);
    expect(available.enabled, isTrue);
    expect(find.text('Already selected'), findsOneWidget);
  });

  testWidgets('search is debounced and displays loading then empty state', (
    tester,
  ) async {
    final pending = Completer<List<DepartureStop>>();
    final repository = FakeStopRepository((_) => pending.future);
    await tester.pumpWidget(app(repository));

    await tester.enterText(
      find.byKey(const Key('stop-search-field')),
      'missing',
    );
    await tester.pump(const Duration(milliseconds: 349));
    expect(repository.queries, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(repository.queries, ['missing']);

    pending.complete(const []);
    await tester.pump();
    expect(find.text('No stops found'), findsOneWidget);
  });

  testWidgets('stale async response is ignored after query changes', (
    tester,
  ) async {
    final first = Completer<List<DepartureStop>>();
    final second = Completer<List<DepartureStop>>();
    final repository = FakeStopRepository(
      (query) => query == 'first' ? first.future : second.future,
    );
    await tester.pumpWidget(app(repository));
    await search(tester, 'first');
    await tester.enterText(
      find.byKey(const Key('stop-search-field')),
      'second',
    );
    first.complete(const [DepartureStop(id: 'stale', name: 'Stale result')]);
    await tester.pump();
    expect(find.text('Stale result'), findsNothing);

    await tester.pump(const Duration(milliseconds: 350));
    second.complete(const [DepartureStop(id: 'fresh', name: 'Fresh result')]);
    await tester.pump();
    expect(find.text('Fresh result'), findsOneWidget);
    expect(find.text('Stale result'), findsNothing);
  });

  testWidgets('error state exposes retry and can recover', (tester) async {
    var fail = true;
    final repository = FakeStopRepository((_) async {
      if (fail) throw const DepartureStopReadException('Stops unavailable.');
      return const [DepartureStop(id: 'jb', name: 'JB Sentral')];
    });
    await tester.pumpWidget(app(repository));
    await search(tester, 'jb');

    expect(find.text('Stops unavailable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('JB Sentral'), findsOneWidget);
    expect(repository.queries, ['jb', 'jb']);
  });

  testWidgets('selector has no overflow in portrait and landscape', (
    tester,
  ) async {
    for (final size in [const Size(400, 800), const Size(800, 400)]) {
      await tester.binding.setSurfaceSize(size);
      final repository = FakeStopRepository(
        (_) async => List.generate(
          50,
          (index) => DepartureStop(id: 'stop-$index', name: 'Stop $index'),
        ),
      );
      await tester.pumpWidget(app(repository));
      await search(tester, 'stop');
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      if (size.width > size.height) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 160);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(const Key('stop-stop-49')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('stop-stop-49')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
    }
    await tester.binding.setSurfaceSize(null);
  });
}
