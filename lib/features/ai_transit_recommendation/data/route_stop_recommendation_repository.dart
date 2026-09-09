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
const maxRouteStopOverallSummaryLength = 600;
const maxRouteStopItemLength = 240;
const maxRouteStopAreaDescriptionLength = 240;
const maxRouteStopIdentityLength = 160;
const maxRouteStopRecommendationGroups = 5;

const routeStopRecommendationInstructions = '''
Use only the supplied compact deterministic evidence for every eligible route. Return one feature-level synthesis and reconcile every eligible route exactly once. Group routes by action and use at most one group for each action. Use only submitted eligible route IDs and route-namespaced evidence-reference IDs. Every group must cite evidence for every route in that group. Do not infer passenger demand, occupancy, capacity, boarding counts, accessibility, safety, land availability, construction feasibility, or population demand. Operational activity is not passenger demand, and zero feedback is not proof that a route or stop is good. Do not fabricate stop coordinates, route geometry, route extensions, endpoints, trip patterns, or operational counts. For additionalStopCoverage, provide exactly one submitted consecutive directed stop pair for each route in that group. Never provide coordinates or a new stop ID. Use insufficientEvidence only for eligible routes that cannot support a responsible recommendation. Return only the requested concise structured result and no hidden reasoning.
''';

const _candidateSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'routeId': {'type': 'string', 'maxLength': maxRouteStopIdentityLength},
    'fromStopId': {'type': 'string', 'maxLength': maxRouteStopIdentityLength},
    'fromStopName': {'type': 'string', 'maxLength': maxRouteStopIdentityLength},
    'toStopId': {'type': 'string', 'maxLength': maxRouteStopIdentityLength},
    'toStopName': {'type': 'string', 'maxLength': maxRouteStopIdentityLength},
    'areaDescription': {
      'type': 'string',
      'maxLength': maxRouteStopAreaDescriptionLength,
    },
  },
  'required': [
    'routeId',
    'fromStopId',
    'fromStopName',
    'toStopId',
    'toStopName',
    'areaDescription',
  ],
  'additionalProperties': false,
};

const _groupSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'action': {
      'type': 'string',
      'enum': [
        'routeImprovement',
        'stopImprovement',
        'additionalStopCoverage',
        'maintainCurrentConfiguration',
        'insufficientEvidence',
      ],
    },
    'summary': {'type': 'string', 'maxLength': maxRouteStopSummaryLength},
    'rationale': {
      'type': 'array',
      'maxItems': maxRouteStopRationaleItems,
      'items': {'type': 'string', 'maxLength': maxRouteStopItemLength},
    },
    'routeIds': {
      'type': 'array',
      'items': {'type': 'string', 'maxLength': maxRouteStopIdentityLength},
    },
    'evidenceReferences': {
      'type': 'array',
      'maxItems': maxRouteStopEvidenceReferenceItems,
      'items': {'type': 'string', 'maxLength': maxRouteStopIdentityLength},
    },
    'limitations': {
      'type': 'array',
      'maxItems': maxRouteStopLimitationItems,
      'items': {'type': 'string', 'maxLength': maxRouteStopItemLength},
    },
    'candidateAreas': {'type': 'array', 'items': _candidateSchema},
  },
  'required': [
    'action',
    'summary',
    'rationale',
    'routeIds',
    'evidenceReferences',
    'limitations',
    'candidateAreas',
  ],
  'additionalProperties': false,
};

const routeStopRecommendationResponseSchema = <String, dynamic>{
  'type': 'object',
  'properties': {
    'overallSummary': {
      'type': 'string',
      'maxLength': maxRouteStopOverallSummaryLength,
    },
    'recommendationGroups': {
      'type': 'array',
      'maxItems': maxRouteStopRecommendationGroups,
      'items': _groupSchema,
    },
  },
  'required': ['overallSummary', 'recommendationGroups'],
  'additionalProperties': false,
};

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
          responseSchema: routeStopRecommendationResponseSchema,
        ),
      );
      final synthesis = parseRouteStopRecommendationSynthesis(
        response.value,
        payload: payload.toJson(),
      );
      return RouteStopRecommendationResult(
        status: synthesis.recommendationGroups.isEmpty
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
  _keys(value, const {'overallSummary', 'recommendationGroups'});
  final overall = _string(
    value['overallSummary'],
    maxRouteStopOverallSummaryLength,
  );
  final rawGroups = value['recommendationGroups'];
  if (rawGroups is! List<dynamic> ||
      rawGroups.isEmpty ||
      rawGroups.length > maxRouteStopRecommendationGroups) {
    _invalid();
  }
  final allowed = (payload['eligible_route_ids'] as List<dynamic>)
      .cast<String>()
      .toSet();
  final routes = <String>{};
  final actions = <RouteStopRecommendationAction>{};
  final groups = <RouteStopRecommendationGroup>[];
  RouteStopRecommendationGroup? insufficient;
  for (final raw in rawGroups) {
    if (raw is! Map<String, dynamic>) _invalid();
    final group = _parseGroup(raw, payload);
    if (!actions.add(group.action) ||
        group.routeIds.any((id) => !allowed.contains(id) || !routes.add(id))) {
      _invalid();
    }
    if (group.action == RouteStopRecommendationAction.insufficientEvidence) {
      insufficient = group;
    } else {
      groups.add(group);
    }
  }
  if (routes.length != allowed.length || !routes.containsAll(allowed)) {
    _invalid();
  }
  return RouteStopRecommendationSynthesis(
    overallSummary: overall,
    recommendationGroups: List.unmodifiable(groups),
    needsMoreEvidence: insufficient,
  );
}

RouteStopRecommendationGroup _parseGroup(
  Map<String, dynamic> value,
  Map<String, dynamic> payload,
) {
  _keys(value, const {
    'action',
    'summary',
    'rationale',
    'routeIds',
    'evidenceReferences',
    'limitations',
    'candidateAreas',
  });
  final action = _action(value['action']);
  final routeIds = _strings(
    value['routeIds'],
    (payload['eligible_route_ids'] as List<dynamic>).length,
    false,
    maxRouteStopIdentityLength,
  );
  final refs = _strings(
    value['evidenceReferences'],
    maxRouteStopEvidenceReferenceItems,
    false,
    maxRouteStopIdentityLength,
  );
  if (routeIds.toSet().length != routeIds.length ||
      refs.toSet().length != refs.length) {
    _invalid();
  }
  final refsByRoute = _references(payload);
  final allowedRefs = <String>{for (final id in routeIds) ...?refsByRoute[id]};
  if (refs.any((ref) => !allowedRefs.contains(ref))) {
    throw const RouteStopRecommendationValidationException(
      failure: RouteStopRecommendationFailure.unknownEvidenceReference,
    );
  }
  for (final id in routeIds) {
    if (!refs.any((ref) => refsByRoute[id]?.contains(ref) == true)) _invalid();
  }
  final rawAreas = value['candidateAreas'];
  if (rawAreas is! List<dynamic> || rawAreas.length > routeIds.length) {
    _invalid();
  }
  final areas = rawAreas
      .map((raw) => _area(raw, payload, routeIds))
      .toList(growable: false);
  if (action == RouteStopRecommendationAction.additionalStopCoverage) {
    final areaRoutes = areas.map((area) => area.routeId).toSet();
    if (areaRoutes.length != areas.length ||
        areaRoutes.length != routeIds.length ||
        !areaRoutes.containsAll(routeIds)) {
      _invalid();
    }
  } else if (areas.isNotEmpty) {
    _invalid();
  }
  final limits = _strings(
    value['limitations'],
    maxRouteStopLimitationItems,
    true,
    maxRouteStopItemLength,
  );
  if (action == RouteStopRecommendationAction.insufficientEvidence &&
      limits.isEmpty) {
    _invalid();
  }
  return RouteStopRecommendationGroup(
    action: action,
    summary: _string(value['summary'], maxRouteStopSummaryLength),
    rationale: List.unmodifiable(
      _strings(
        value['rationale'],
        maxRouteStopRationaleItems,
        false,
        maxRouteStopItemLength,
      ),
    ),
    routeIds: List.unmodifiable(routeIds),
    evidenceReferences: List.unmodifiable(refs),
    limitations: List.unmodifiable(limits),
    candidateAreas: List.unmodifiable(areas),
  );
}

Map<String, Set<String>> _references(Map<String, dynamic> payload) {
  final result = <String, Set<String>>{};
  final routes = payload['routes'];
  if (routes is! List<dynamic>) _invalid();
  for (final route in routes) {
    if (route is! Map<String, dynamic>) _invalid();
    final identity = route['route'];
    final refs = route['evidence_references'];
    if (identity is! Map<String, dynamic> ||
        identity['route_id'] is! String ||
        refs is! List<dynamic> ||
        refs.any((ref) => ref is! String)) {
      _invalid();
    }
    result[identity['route_id'] as String] = refs.cast<String>().toSet();
  }
  return result;
}

RouteStopCandidateArea _area(
  Object? raw,
  Map<String, dynamic> payload,
  List<String> routeIds,
) {
  if (raw is! Map<String, dynamic>) _invalid();
  _keys(raw, const {
    'routeId',
    'fromStopId',
    'fromStopName',
    'toStopId',
    'toStopName',
    'areaDescription',
  });
  final routeId = _string(raw['routeId'], maxRouteStopIdentityLength);
  final fromId = _string(raw['fromStopId'], maxRouteStopIdentityLength);
  final fromName = _string(raw['fromStopName'], maxRouteStopIdentityLength);
  final toId = _string(raw['toStopId'], maxRouteStopIdentityLength);
  final toName = _string(raw['toStopName'], maxRouteStopIdentityLength);
  if (!routeIds.contains(routeId) ||
      !_pair(payload, routeId, fromId, fromName, toId, toName)) {
    throw const RouteStopRecommendationValidationException(
      failure: RouteStopRecommendationFailure.unknownStopReference,
    );
  }
  return RouteStopCandidateArea(
    routeId: routeId,
    fromStopId: fromId,
    fromStopName: fromName,
    toStopId: toId,
    toStopName: toName,
    areaDescription: _string(
      raw['areaDescription'],
      maxRouteStopAreaDescriptionLength,
    ),
  );
}

bool _pair(
  Map<String, dynamic> payload,
  String routeId,
  String fromId,
  String fromName,
  String toId,
  String toName,
) {
  final routes = payload['routes'];
  if (routes is! List<dynamic>) return false;
  final route = routes.whereType<Map<String, dynamic>>().where((item) {
    final identity = item['route'];
    return identity is Map<String, dynamic> && identity['route_id'] == routeId;
  }).firstOrNull;
  final network = route?['network'];
  if (network is! Map<String, dynamic>) return false;
  final catalog = network['stop_catalog'];
  if (catalog is! List<dynamic>) return false;
  final names = <String, String?>{};
  for (final stop in catalog) {
    if (stop is! Map<String, dynamic> ||
        stop['stop_id'] is! String ||
        (stop['stop_name'] != null && stop['stop_name'] is! String)) {
      return false;
    }
    final id = stop['stop_id'] as String;
    final name = stop['stop_name'] as String?;
    if (names.containsKey(id) && names[id] != name) return false;
    names[id] = name;
  }
  if (names[fromId] != fromName || names[toId] != toName) return false;
  final patterns = network['trip_patterns'];
  if (patterns is! List<dynamic>) return false;
  for (final pattern in patterns.whereType<Map<String, dynamic>>()) {
    final stops = pattern['ordered_stops'];
    if (stops is! List<dynamic>) continue;
    for (var i = 0; i + 1 < stops.length; i++) {
      final from = stops[i];
      final to = stops[i + 1];
      if (from is Map<String, dynamic> &&
          to is Map<String, dynamic> &&
          from['stop_id'] == fromId &&
          to['stop_id'] == toId) {
        return true;
      }
    }
  }
  return false;
}

void _keys(Map<String, dynamic> value, Set<String> expected) {
  if (value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    _invalid();
  }
}

RouteStopRecommendationAction _action(Object? value) =>
    RouteStopRecommendationAction.values
        .where((item) => item.name == value)
        .firstOrNull ??
    _invalid();
String _string(Object? value, int max) {
  if (value is! String || value.trim().isEmpty || value.length > max) {
    _invalid();
  }
  return value.trim();
}

List<String> _strings(Object? value, int maxItems, bool empty, int maxLength) {
  if (value is! List<dynamic> ||
      value.length > maxItems ||
      (!empty && value.isEmpty)) {
    _invalid();
  }
  return value.map((item) => _string(item, maxLength)).toList(growable: false);
}

Never _invalid() => throw const RouteStopRecommendationValidationException(
  failure: RouteStopRecommendationFailure.invalidResponse,
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
    httpStatusCode: error.failure == GeminiTransportFailure.http
        ? error.statusCode
        : null,
  );
}
