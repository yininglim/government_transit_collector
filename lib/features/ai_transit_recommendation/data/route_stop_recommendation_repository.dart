import 'dart:convert';

import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_repository.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_data_source.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_evidence_payloads.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/gemini_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_recommendation_models.dart';

const routeStopRecommendationTimeout = Duration(seconds: 90);
const maxRouteStopRationaleItems = 4;
const maxRouteStopLimitationItems = 4;
const maxRouteStopEvidenceReferenceItems = 40;
const maxRouteStopSummaryLength = 240;
const maxRouteStopOverallSummaryLength = 480;
const maxRouteStopItemLength = 240;
const maxRouteStopAreaDescriptionLength = 240;
const maxRouteStopIdentityLength = 160;
const maxRouteStopRecommendationRecords = 100;

const routeStopRecommendationInstructions = '''
Interpret compact input exactly: shared_stop_catalog is factual metadata for globally unique stops, not route membership. Each route's served_stop_ids is authoritative; never infer membership from shared metadata. ordered_stop_field_order defines every positional ordered-stop row, which must be read by that order. Trip patterns retain route-specific order and schedule evidence. For additionalStopCoverage, use one same-route pair that is consecutive in the directed order of that route's retained pattern. Reversed, cross-route, non-adjacent, and fabricated pairs are forbidden.
Use only deterministic evidence. Return one routeRecommendation record for every eligible route, exactly once. A record may contain multiple compatible improvement actions: routeImprovement, stopImprovement, and additionalStopCoverage. maintainCurrentConfiguration and insufficientEvidence are exclusive and must each appear alone. Use only submitted route IDs. For each routeRecommendation, copy routeOwnedEvidenceRefs verbatim only from that route object's evidence_references array, with at least one reference; do not use nested evidence_ref or evidence_refs as the output source, remove or alter the route namespace, construct references manually, or use another route's references. Do not repeat deterministic values or infer passenger demand, occupancy, capacity, accessibility, safety, feasibility, population, or unsupported operations. Do not fabricate route IDs, stop IDs, evidence references, coordinates, geometry, trip patterns, counts, or locations. Return only the concise structured result.
Keep overallSummary non-empty and at most 480 characters, every conciseRationale non-empty and at most 240 characters, and every routeOwnedEvidenceRefs between 1 and 40 items. Limit limitations to four non-empty items of at most 240 characters each. For insufficientEvidence, use it alone and include at least one concise limitation; otherwise limitations is optional.
If actions contains stopImprovement, return 1-3 targetStopIds copied verbatim from that route's served_stop_ids. Choose only existing stops whose supplied deterministic metadata has a usable name and valid coordinates; never construct an ID or use a stop belonging only to another route. Omit targetStopIds when stopImprovement is absent. targetStopIds identify existing stops to improve; candidateArea remains exclusively for additionalStopCoverage.
''';

const _candidateSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'fromStopId': {'type': 'string'},
    'toStopId': {'type': 'string'},
  },
  'required': ['fromStopId', 'toStopId'],
  'additionalProperties': false,
};

const _routeRecommendationSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'routeId': {'type': 'string'},
    'actions': {
      'type': 'array',
      'minItems': 1,
      'maxItems': 3,
      'items': {
        'type': 'string',
        'enum': [
          'routeImprovement',
          'stopImprovement',
          'additionalStopCoverage',
          'maintainCurrentConfiguration',
          'insufficientEvidence',
        ],
      },
    },
    'conciseRationale': {'type': 'string'},
    'routeOwnedEvidenceRefs': {
      'type': 'array',
      'maxItems': maxRouteStopEvidenceReferenceItems,
      'items': {'type': 'string'},
    },
    'targetStopIds': {
      'type': 'array',
      'maxItems': 3,
      'items': {'type': 'string'},
    },
    'limitations': {
      'type': 'array',
      'maxItems': maxRouteStopLimitationItems,
      'items': {'type': 'string'},
    },
    'candidateArea': _candidateSchema,
  },
  'required': [
    'routeId',
    'actions',
    'conciseRationale',
    'routeOwnedEvidenceRefs',
  ],
  'additionalProperties': false,
};

Map<String, dynamic> routeStopRecommendationResponseSchemaFor(int routeCount) =>
    {
      'type': 'object',
      'properties': {
        'overallSummary': {
          'type': 'string',
        },
        'routeRecommendations': {
          'type': 'array',
          'items': _routeRecommendationSchema,
        },
      },
      'required': ['overallSummary', 'routeRecommendations'],
      'additionalProperties': false,
    };

final routeStopRecommendationResponseSchema =
    routeStopRecommendationResponseSchemaFor(1);

abstract interface class RouteStopRecommendationRepository {
  Future<RouteStopRecommendationResult> generate({
    required List<DistrictRouteStopEvidence> evidence,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  });
}

class DefaultRouteStopRecommendationRepository
    implements RouteStopRecommendationRepository {
  DefaultRouteStopRecommendationRepository({
    DistrictRouteStopEvidenceRepository? evidenceRepository,
    RouteStopGeminiPayloadBuilder? payloadBuilder,
    GeminiDataSource? geminiDataSource,
    this.requestTimeout = routeStopRecommendationTimeout,
  }) : _payloadBuilder =
           payloadBuilder ?? const RouteStopGeminiPayloadBuilder(),
       _geminiDataSource =
           geminiDataSource ??
           GeminiInteractionsDataSource(requestTimeout: requestTimeout);
  final RouteStopGeminiPayloadBuilder _payloadBuilder;
  final GeminiDataSource _geminiDataSource;
  final Duration requestTimeout;

  @override
  Future<RouteStopRecommendationResult> generate({
    required List<DistrictRouteStopEvidence> evidence,
    required DateTime startUtc,
    required DateTime endExclusiveUtc,
  }) async {
    final retained = List<DistrictRouteStopEvidence>.unmodifiable(evidence);
    if (retained.isEmpty) {
      return _failure(
        RouteStopRecommendationStatus.insufficientEvidence,
        RouteStopRecommendationFailure.evidenceUnavailable,
        retained,
      );
    }
    try {
      _validateRetained(retained, startUtc, endExclusiveUtc);
    } on Object {
      return _failure(
        RouteStopRecommendationStatus.temporarilyUnavailable,
        RouteStopRecommendationFailure.evidenceUnavailable,
        retained,
      );
    }
    late final RouteStopGeminiEvidencePayload payload;
    try {
      payload = _payloadBuilder.buildFeature(retained);
    } on RouteStopGeminiPayloadBuildException {
      return _failure(
        RouteStopRecommendationStatus.temporarilyUnavailable,
        RouteStopRecommendationFailure.evidenceUnavailable,
        retained,
      );
    }
    try {
      final response = await _geminiDataSource.createStructuredInteraction(
        GeminiStructuredInteractionRequest(
          input: jsonEncode(payload.toJson()),
          instructions: routeStopRecommendationInstructions,
          responseSchema: routeStopRecommendationResponseSchemaFor(
            retained.length,
          ),
        ),
      );
      final synthesis = parseRouteStopRecommendationSynthesis(
        response.value,
        payload: payload.toJson(),
      );
      return RouteStopRecommendationResult(
        status: synthesis.recommendationGroups.every(
              (group) =>
                  group.action ==
                  RouteStopRecommendationAction.insufficientEvidence,
            )
            ? RouteStopRecommendationStatus.insufficientEvidence
            : RouteStopRecommendationStatus.available,
        synthesis: synthesis,
        failure: null,
        evidence: retained,
        payload: payload,
      );
    } on RouteStopRecommendationValidationException catch (error) {
      return RouteStopRecommendationResult(
        status: RouteStopRecommendationStatus.invalidAiResponse,
        synthesis: null,
        failure: error.failure,
        evidence: retained,
        payload: payload,
      );
    } on GeminiTransportException catch (error) {
      return _transportFailure(error, retained, payload);
    }
  }
}

RouteStopRecommendationResult _failure(
  RouteStopRecommendationStatus status,
  RouteStopRecommendationFailure failure,
  List<DistrictRouteStopEvidence> evidence,
) => RouteStopRecommendationResult(
  status: status,
  synthesis: null,
  failure: failure,
  evidence: evidence,
  payload: null,
);

void _validateRetained(
  List<DistrictRouteStopEvidence> evidence,
  DateTime start,
  DateTime end,
) {
  final ids = <String>{};
  for (final item in evidence) {
    final source = item.routeStopEvidence;
    if (source.routeId.trim().isEmpty ||
        source.network.route.routeId != source.routeId ||
        !ids.add(source.routeId) ||
        !source.periodStart.isAtSameMomentAs(start) ||
        !source.periodEnd.isAtSameMomentAs(end) ||
        !source.network.trips.any(
          (trip) =>
              trip.tripId.trim().isNotEmpty &&
              trip.stops
                      .where((stop) => stop.stopId.trim().isNotEmpty)
                      .length >=
                  2,
        )) {
      throw ArgumentError();
    }
  }
}

RouteStopRecommendationSynthesis parseRouteStopRecommendationSynthesis(
  Map<String, dynamic> value, {
  required Map<String, dynamic> payload,
}) {
  _keys(value, const {'overallSummary', 'routeRecommendations'});
  final overall = _string(
    value['overallSummary'],
    maxRouteStopOverallSummaryLength,
    RouteStopInvalidField.overallSummary,
  );
  final rawRecords = value['routeRecommendations'];
  if (rawRecords is! List<dynamic> ||
      rawRecords.isEmpty ||
      rawRecords.length > maxRouteStopRecommendationRecords) {
    _invalid(
      RouteStopValidationDiagnostic.invalidField,
      RouteStopInvalidField.routeRecommendations,
    );
  }
  final allowed = (payload['eligible_route_ids'] as List<dynamic>)
      .cast<String>()
      .toSet();
  final records = <RouteStopRecommendationRecord>[];
  final seenRoutes = <String>{};
  for (final raw in rawRecords) {
    if (raw is! Map<String, dynamic>) {
      _invalid(
        RouteStopValidationDiagnostic.invalidField,
        RouteStopInvalidField.routeRecommendations,
      );
    }
    final rawRouteId = raw['routeId'];
    if (rawRouteId is! String || !allowed.contains(rawRouteId)) {
      _invalid(RouteStopValidationDiagnostic.unknownRoute);
    }
    final record = _parseRecord(raw, payload);
    if (!seenRoutes.add(record.routeId)) {
      _invalid(RouteStopValidationDiagnostic.duplicateRoute);
    }
    records.add(record);
  }
  if (seenRoutes.length != allowed.length || !seenRoutes.containsAll(allowed)) {
    _invalid(RouteStopValidationDiagnostic.missingRoute);
  }
  final groups = groupRouteStopRecommendations(records);
  return RouteStopRecommendationSynthesis(
    overallSummary: overall,
    recommendationGroups: List.unmodifiable(groups),
    needsMoreEvidence: groups
        .where(
          (group) =>
              group.action ==
              RouteStopRecommendationAction.insufficientEvidence,
        )
        .firstOrNull,
    routeRecommendations: List.unmodifiable(records),
  );
}

RouteStopRecommendationRecord _parseRecord(
  Map<String, dynamic> value,
  Map<String, dynamic> payload,
) {
  _keysOptional(
    value,
    const {'routeId', 'actions', 'conciseRationale', 'routeOwnedEvidenceRefs'},
    const {'candidateArea', 'limitations', 'targetStopIds'},
  );
  final routeId = _string(
    value['routeId'],
    maxRouteStopIdentityLength,
    RouteStopInvalidField.routeId,
  );
  final actions = _actions(value['actions']);
  final rationale = _string(
    value['conciseRationale'],
    maxRouteStopItemLength,
    RouteStopInvalidField.conciseRationale,
  );
  final refs = _strings(
    value['routeOwnedEvidenceRefs'],
    maxRouteStopEvidenceReferenceItems,
    false,
    maxRouteStopIdentityLength,
    RouteStopInvalidField.routeOwnedEvidenceRefs,
  );
  if (refs.toSet().length != refs.length) {
    _invalid(RouteStopValidationDiagnostic.duplicateEvidenceReference);
  }
  final refsByRoute = _references(payload);
  final allowedRefs = refsByRoute[routeId] ?? const <String>{};
  final allRefs = <String>{for (final refs in refsByRoute.values) ...refs};
  final invalidReference = refs
      .where((ref) => !allowedRefs.contains(ref))
      .firstOrNull;
  if (invalidReference != null) {
    throw RouteStopRecommendationValidationException(
      failure: RouteStopRecommendationFailure.unknownEvidenceReference,
      diagnostic: allRefs.contains(invalidReference)
          ? RouteStopValidationDiagnostic.crossRouteEvidenceReference
          : RouteStopValidationDiagnostic.unknownEvidenceReference,
    );
  }
  if (refs.isEmpty || !refs.any(allowedRefs.contains)) {
    _invalid(RouteStopValidationDiagnostic.missingEvidenceReference);
  }
  final hasStopImprovement = actions.contains(
    RouteStopRecommendationAction.stopImprovement,
  );
  final rawTargetStopIds = value['targetStopIds'];
  List<String> targetStopIds = const [];
  if (hasStopImprovement) {
    if (rawTargetStopIds == null) {
      _invalid(RouteStopValidationDiagnostic.targetStopsRequired);
    }
    if (rawTargetStopIds is List<dynamic> &&
        rawTargetStopIds.any(
          (item) => item is String && item != item.trim(),
        )) {
      _invalid(
        RouteStopValidationDiagnostic.invalidField,
        RouteStopInvalidField.targetStopIds,
      );
    }
    targetStopIds = _strings(
      rawTargetStopIds,
      3,
      false,
      maxRouteStopIdentityLength,
      RouteStopInvalidField.targetStopIds,
    );
    if (targetStopIds.toSet().length != targetStopIds.length) {
      _invalid(RouteStopValidationDiagnostic.duplicateTargetStop);
    }
    _validateTargetStops(payload, routeId, targetStopIds);
  } else if (rawTargetStopIds != null) {
    _invalid(RouteStopValidationDiagnostic.targetStopsProhibited);
  }
  final hasAdditional = actions.contains(
    RouteStopRecommendationAction.additionalStopCoverage,
  );
  final rawArea = value['candidateArea'];
  RouteStopCandidateArea? candidateArea;
  if (hasAdditional) {
    if (rawArea == null) {
      _invalid(RouteStopValidationDiagnostic.candidateAreaRequired);
    }
    candidateArea = _area(rawArea, payload, routeId);
  } else if (rawArea != null) {
    _invalid(RouteStopValidationDiagnostic.candidateAreaProhibited);
  }
  final rawLimits = value['limitations'];
  final limits = rawLimits == null
      ? const <String>[]
      : _strings(
          rawLimits,
          maxRouteStopLimitationItems,
          true,
          maxRouteStopItemLength,
          RouteStopInvalidField.limitations,
        );
  if (actions.contains(RouteStopRecommendationAction.insufficientEvidence) &&
      limits.isEmpty) {
    _invalid(
      RouteStopValidationDiagnostic.invalidField,
      RouteStopInvalidField.insufficientEvidenceLimitations,
    );
  }
  final exclusive =
      actions.contains(
        RouteStopRecommendationAction.maintainCurrentConfiguration,
      ) ||
      actions.contains(RouteStopRecommendationAction.insufficientEvidence);
  if (exclusive && actions.length != 1) {
    _invalid(RouteStopValidationDiagnostic.incompatibleActionCombination);
  }
  return RouteStopRecommendationRecord(
    routeId: routeId,
    actions: List.unmodifiable(actions),
    conciseRationale: rationale,
    routeOwnedEvidenceRefs: List.unmodifiable(refs),
    targetStopIds: List.unmodifiable(targetStopIds),
    candidateArea: candidateArea,
    limitations: List.unmodifiable(limits),
  );
}

List<RouteStopRecommendationAction> _actions(Object? value) {
  if (value is! List<dynamic> || value.isEmpty || value.length > 3) {
    _invalid(RouteStopValidationDiagnostic.emptyActionList);
  }
  final actions = value.map(_action).toList(growable: false);
  if (actions.toSet().length != actions.length) {
    _invalid(RouteStopValidationDiagnostic.duplicateAction);
  }
  return actions;
}

List<RouteStopRecommendationGroup> groupRouteStopRecommendations(
  List<RouteStopRecommendationRecord> records,
) {
  final grouped = <RouteStopRecommendationAction, List<String>>{};
  final refs = <RouteStopRecommendationAction, List<String>>{};
  final areas = <RouteStopRecommendationAction, List<RouteStopCandidateArea>>{};
  for (final record in records) {
    for (final action in record.actions) {
      grouped.putIfAbsent(action, () => []).add(record.routeId);
      refs.putIfAbsent(action, () => []).addAll(record.routeOwnedEvidenceRefs);
      if (action == RouteStopRecommendationAction.additionalStopCoverage &&
          record.candidateArea != null) {
        areas.putIfAbsent(action, () => []).add(record.candidateArea!);
      }
    }
  }
  final order = RouteStopRecommendationAction.values;
  return [
    for (final action in order)
      if (grouped[action]?.isNotEmpty == true)
        RouteStopRecommendationGroup(
          action: action,
          summary: _groupSummary(action),
          rationale: const [],
          evidenceReferences: List.unmodifiable(refs[action] ?? const []),
          limitations: const [],
          routeIds: List.unmodifiable(grouped[action]!),
          candidateAreas: List.unmodifiable(areas[action] ?? const []),
        ),
  ];
}

String _groupSummary(RouteStopRecommendationAction action) => switch (action) {
  RouteStopRecommendationAction.routeImprovement =>
    'Validated route improvement recommendations.',
  RouteStopRecommendationAction.stopImprovement =>
    'Validated stop improvement recommendations.',
  RouteStopRecommendationAction.additionalStopCoverage =>
    'Validated additional stop coverage recommendations.',
  RouteStopRecommendationAction.maintainCurrentConfiguration =>
    'Routes supported by the current configuration.',
  RouteStopRecommendationAction.insufficientEvidence =>
    'Routes requiring more evidence before an actionable recommendation.',
};

Map<String, Set<String>> _references(Map<String, dynamic> payload) {
  final result = <String, Set<String>>{};
  final routes = payload['routes'];
  if (routes is! List<dynamic>) {
    _invalid(
      RouteStopValidationDiagnostic.invalidField,
      RouteStopInvalidField.routeRecommendations,
    );
  }
  for (final route in routes) {
    if (route is! Map<String, dynamic>) {
      _invalid(
        RouteStopValidationDiagnostic.invalidField,
        RouteStopInvalidField.routeRecommendations,
      );
    }
    final identity = route['route'];
    final refs = route['evidence_references'];
    if (identity is! Map<String, dynamic> ||
        identity['route_id'] is! String ||
        refs is! List<dynamic> ||
        refs.any((ref) => ref is! String)) {
      _invalid(
        RouteStopValidationDiagnostic.invalidField,
        RouteStopInvalidField.routeRecommendations,
      );
    }
    result[identity['route_id'] as String] = refs.cast<String>().toSet();
  }
  return result;
}

void _validateTargetStops(
  Map<String, dynamic> payload,
  String routeId,
  List<String> targetStopIds,
) {
  final routes = payload['routes'];
  final catalog = payload['shared_stop_catalog'];
  if (routes is! List<dynamic> || catalog is! Map<String, dynamic>) {
    _invalid(
      RouteStopValidationDiagnostic.unavailableTargetStop,
      RouteStopInvalidField.targetStopIds,
    );
  }
  final stopsByRoute = <String, Set<String>>{};
  for (final route in routes) {
    if (route is! Map<String, dynamic>) continue;
    final identity = route['route'];
    final network = route['network'];
    final id = identity is Map<String, dynamic> ? identity['route_id'] : null;
    final served = network is Map<String, dynamic>
        ? network['served_stop_ids']
        : null;
    if (id is String &&
        served is List<dynamic> &&
        served.every((stopId) => stopId is String)) {
      stopsByRoute[id] = served.cast<String>().toSet();
    }
  }
  final routeStops = stopsByRoute[routeId] ?? const <String>{};
  final allStops = <String>{for (final stops in stopsByRoute.values) ...stops};
  for (final stopId in targetStopIds) {
    if (!routeStops.contains(stopId)) {
      throw RouteStopRecommendationValidationException(
        failure: RouteStopRecommendationFailure.unknownStopReference,
        diagnostic: allStops.contains(stopId)
            ? RouteStopValidationDiagnostic.crossRouteTargetStop
            : RouteStopValidationDiagnostic.unknownTargetStop,
        invalidField: RouteStopInvalidField.targetStopIds,
      );
    }
    final entry = catalog[stopId];
    final name = entry is Map<String, dynamic> ? entry['stop_name'] : null;
    final latitude = entry is Map<String, dynamic> ? entry['latitude'] : null;
    final longitude = entry is Map<String, dynamic>
        ? entry['longitude']
        : null;
    final lat = latitude is num ? latitude.toDouble() : null;
    final lng = longitude is num ? longitude.toDouble() : null;
    if (name is! String ||
        name.trim().isEmpty ||
        lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      _invalid(
        RouteStopValidationDiagnostic.unavailableTargetStop,
        RouteStopInvalidField.targetStopIds,
      );
    }
  }
}

RouteStopCandidateArea _area(
  Object? raw,
  Map<String, dynamic> payload,
  String routeId,
) {
  if (raw is! Map<String, dynamic>) {
    _invalid(RouteStopValidationDiagnostic.invalidCandidatePair);
  }
  _keys(raw, const {'fromStopId', 'toStopId'});
  final fromId = _string(
    raw['fromStopId'],
    maxRouteStopIdentityLength,
    RouteStopInvalidField.candidateAreaFromStopId,
  );
  final toId = _string(
    raw['toStopId'],
    maxRouteStopIdentityLength,
    RouteStopInvalidField.candidateAreaToStopId,
  );
  final pairDiagnostic = _candidatePairDiagnostic(
    payload,
    routeId,
    fromId,
    toId,
  );
  if (pairDiagnostic != null) {
    throw RouteStopRecommendationValidationException(
      failure: RouteStopRecommendationFailure.unknownStopReference,
      diagnostic: pairDiagnostic,
    );
  }
  return RouteStopCandidateArea(
    routeId: routeId,
    fromStopId: fromId,
    fromStopName: _stopName(payload, fromId),
    toStopId: toId,
    toStopName: _stopName(payload, toId),
    areaDescription:
        'Between ${_stopName(payload, fromId)} and ${_stopName(payload, toId)}',
  );
}

String _stopName(Map<String, dynamic> payload, String stopId) {
  final catalog = payload['shared_stop_catalog'];
  final entry = catalog is Map<String, dynamic> ? catalog[stopId] : null;
  final name = entry is Map<String, dynamic> ? entry['stop_name'] : null;
  return name is String && name.trim().isNotEmpty ? name : stopId;
}

RouteStopValidationDiagnostic? _candidatePairDiagnostic(
  Map<String, dynamic> payload,
  String routeId,
  String fromId,
  String toId,
) {
  final routes = payload['routes'];
  if (routes is! List<dynamic>) {
    return RouteStopValidationDiagnostic.invalidCandidatePair;
  }
  final route = routes.whereType<Map<String, dynamic>>().where((item) {
    final identity = item['route'];
    return identity is Map<String, dynamic> && identity['route_id'] == routeId;
  }).firstOrNull;
  final network = route?['network'];
  if (network is! Map<String, dynamic>) {
    return RouteStopValidationDiagnostic.invalidCandidatePair;
  }
  final servedStops = network['served_stop_ids'];
  final catalog = payload['shared_stop_catalog'];
  final fieldOrder = payload['ordered_stop_field_order'];
  if (servedStops is! List<dynamic> ||
      servedStops.any((stop) => stop is! String) ||
      catalog is! Map<String, dynamic> ||
      fieldOrder is! List<dynamic> ||
      fieldOrder.length !=
          RouteStopGeminiPayloadBuilder.orderedStopFieldOrder.length ||
      Iterable<int>.generate(fieldOrder.length).any(
        (index) =>
            fieldOrder[index] !=
            RouteStopGeminiPayloadBuilder.orderedStopFieldOrder[index],
      )) {
    return RouteStopValidationDiagnostic.invalidCandidatePair;
  }
  final names = <String, String?>{};
  for (final stopId in servedStops.cast<String>()) {
    final stop = catalog[stopId];
    if (stop is! Map<String, dynamic> ||
        (stop['stop_name'] != null && stop['stop_name'] is! String)) {
      return RouteStopValidationDiagnostic.invalidCandidatePair;
    }
    final name = stop['stop_name'] as String?;
    if (names.containsKey(stopId) && names[stopId] != name) {
      return RouteStopValidationDiagnostic.invalidCandidatePair;
    }
    names[stopId] = name;
  }
  if (!names.containsKey(fromId) || !names.containsKey(toId)) {
    return RouteStopValidationDiagnostic.invalidCandidatePair;
  }
  final patterns = network['trip_patterns'];
  if (patterns is! List<dynamic>) {
    return RouteStopValidationDiagnostic.invalidCandidatePair;
  }
  var reversed = false;
  var nonAdjacent = false;
  for (final pattern in patterns.whereType<Map<String, dynamic>>()) {
    final stops = pattern['ordered_stops'];
    if (stops is! List<dynamic>) continue;
    final ids = <Object?>[
      for (final stop in stops)
        stop is List<dynamic> && stop.isNotEmpty ? stop.first : null,
    ];
    for (var i = 0; i + 1 < stops.length; i++) {
      final from = stops[i];
      final to = stops[i + 1];
      if (from is List<dynamic> &&
          to is List<dynamic> &&
          from.length ==
              RouteStopGeminiPayloadBuilder.orderedStopFieldOrder.length &&
          to.length ==
              RouteStopGeminiPayloadBuilder.orderedStopFieldOrder.length &&
          from[0] == fromId &&
          to[0] == toId) {
        return null;
      }
      if (from is List<dynamic> &&
          to is List<dynamic> &&
          from.isNotEmpty &&
          to.isNotEmpty &&
          from[0] == toId &&
          to[0] == fromId) {
        reversed = true;
      }
    }
    if (ids.contains(fromId) && ids.contains(toId)) nonAdjacent = true;
  }
  if (reversed) return RouteStopValidationDiagnostic.reversedCandidatePair;
  if (nonAdjacent) {
    return RouteStopValidationDiagnostic.nonAdjacentCandidatePair;
  }
  return RouteStopValidationDiagnostic.invalidCandidatePair;
}

void _keys(Map<String, dynamic> value, Set<String> expected) {
  if (expected.difference(value.keys.toSet()).isNotEmpty) {
    _invalid(RouteStopValidationDiagnostic.missingRequiredField);
  }
  if (value.keys.toSet().difference(expected).isNotEmpty) {
    _invalid(RouteStopValidationDiagnostic.unknownProperty);
  }
}

void _keysOptional(
  Map<String, dynamic> value,
  Set<String> required,
  Set<String> optional,
) {
  if (required.difference(value.keys.toSet()).isNotEmpty) {
    _invalid(RouteStopValidationDiagnostic.missingRequiredField);
  }
  if (value.keys.toSet().difference({...required, ...optional}).isNotEmpty) {
    _invalid(RouteStopValidationDiagnostic.unknownProperty);
  }
}

RouteStopRecommendationAction _action(Object? value) =>
    RouteStopRecommendationAction.values
        .where((item) => item.name == value)
        .firstOrNull ??
    _invalid(RouteStopValidationDiagnostic.invalidAction);
String _string(Object? value, int max, RouteStopInvalidField field) {
  if (value is! String || value.trim().isEmpty || value.length > max) {
    _invalid(RouteStopValidationDiagnostic.invalidField, field);
  }
  return value.trim();
}

List<String> _strings(
  Object? value,
  int maxItems,
  bool empty,
  int maxLength,
  RouteStopInvalidField field,
) {
  if (value is! List<dynamic> ||
      value.length > maxItems ||
      (!empty && value.isEmpty)) {
    _invalid(RouteStopValidationDiagnostic.invalidField, field);
  }
  return value
      .map((item) => _string(item, maxLength, field))
      .toList(growable: false);
}

Never _invalid(
  RouteStopValidationDiagnostic diagnostic, [
  RouteStopInvalidField? invalidField,
]) =>
    throw RouteStopRecommendationValidationException(
      failure: RouteStopRecommendationFailure.invalidResponse,
      diagnostic: diagnostic,
      invalidField: invalidField,
    );

RouteStopRecommendationResult _transportFailure(
  GeminiTransportException error,
  List<DistrictRouteStopEvidence> evidence,
  RouteStopGeminiEvidencePayload payload,
) {
  final failure = switch (error.failure) {
    GeminiTransportFailure.notConfigured =>
      RouteStopRecommendationFailure.geminiNotConfigured,
    GeminiTransportFailure.timeout => RouteStopRecommendationFailure.timeout,
    GeminiTransportFailure.rateLimited =>
      RouteStopRecommendationFailure.rateLimited,
    GeminiTransportFailure.authentication =>
      RouteStopRecommendationFailure.authentication,
    GeminiTransportFailure.malformedResponse ||
    GeminiTransportFailure.missingStructuredOutput ||
    GeminiTransportFailure.invalidStructuredJson =>
      RouteStopRecommendationFailure.malformedResponse,
    GeminiTransportFailure.network => RouteStopRecommendationFailure.network,
    GeminiTransportFailure.http => RouteStopRecommendationFailure.http,
  };
  return RouteStopRecommendationResult(
    status: failure == RouteStopRecommendationFailure.malformedResponse
        ? RouteStopRecommendationStatus.invalidAiResponse
        : RouteStopRecommendationStatus.temporarilyUnavailable,
    synthesis: null,
    failure: failure,
    evidence: evidence,
    payload: payload,
  );
}
