import 'package:government_transit_collector/features/ai_transit_recommendation/data/bus_frequency_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/district_route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/fuel_cost_calculation_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/operational_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/route_stop_evidence_models.dart';
import 'package:government_transit_collector/features/ai_transit_recommendation/data/scheduled_service_evidence_models.dart';
import 'package:government_transit_collector/features/route_performance/data/route_performance_models.dart';

const maxPayloadDirectionGroups = 4;
const maxPayloadHourlyBucketsPerDirection = 168;
const maxPayloadIncompleteTripIds = 100;
const maxPayloadPeakBuckets = 48;
const maxPayloadTripVariants = 20;
const maxPayloadStopsPerTrip = 100;
const maxPayloadUncostableDepartures = 100;

abstract interface class GeminiEvidencePayload {
  Map<String, dynamic> toJson();
}

class BusFrequencyGeminiEvidencePayload implements GeminiEvidencePayload {
  const BusFrequencyGeminiEvidencePayload(this._json);

  final Map<String, dynamic> _json;

  @override
  Map<String, dynamic> toJson() => _json;
}

class RouteStopGeminiEvidencePayload implements GeminiEvidencePayload {
  const RouteStopGeminiEvidencePayload(this._json);

  final Map<String, dynamic> _json;

  @override
  Map<String, dynamic> toJson() => _json;
}

class CostGeminiEvidencePayload implements GeminiEvidencePayload {
  const CostGeminiEvidencePayload(this._json);

  final Map<String, dynamic> _json;

  @override
  Map<String, dynamic> toJson() => _json;
}

class BusFrequencyGeminiPayloadBuilder {
  const BusFrequencyGeminiPayloadBuilder();

  BusFrequencyGeminiEvidencePayload build(BusFrequencyEvidence evidence) {
    final scheduled = evidence.scheduledService;
    final includedDirections = scheduled.directionGroups
        .take(maxPayloadDirectionGroups)
        .toList(growable: false);
    final references = <String>{
      'scheduled.summary',
      'operational.peak_operation',
      'operational.route_performance',
      'feedback.bus_was_late',
      'feedback.bus_overcrowded',
      'feedback.bus_did_not_arrive',
    };
    final directions = <Map<String, dynamic>>[];
    for (var index = 0; index < includedDirections.length; index++) {
      final direction = includedDirections[index];
      final reference = 'scheduled.direction.$index';
      references.add(reference);
      directions.add({
        'evidence_ref': reference,
        'direction_id': direction.directionId,
        'departure_count': direction.departures.length,
        'average_headway_seconds': _finite(direction.averageHeadwaySeconds),
        'median_headway_seconds': _finite(direction.medianHeadwaySeconds),
        'minimum_headway_seconds': direction.minimumHeadwaySeconds,
        'maximum_headway_seconds': direction.maximumHeadwaySeconds,
        'hourly_service': direction.hourlyBuckets
            .take(maxPayloadHourlyBucketsPerDirection)
            .map(
              (bucket) => {
                'service_date': _date(bucket.serviceDate),
                'start_minute': bucket.startMinute,
                'scheduled_departure_count': bucket.scheduledDepartureCount,
                'scheduled_trips_per_hour': _finite(
                  bucket.scheduledTripsPerHour,
                ),
              },
            )
            .toList(growable: false),
        'omitted_hourly_bucket_count':
            (direction.hourlyBuckets.length -
                    maxPayloadHourlyBucketsPerDirection)
                .clamp(0, direction.hourlyBuckets.length),
      });
    }
    final issueCounts = evidence.feedback.countByIssueType;
    final limitations = <String>[
      if (scheduled.status != ScheduledServiceEvidenceStatus.available)
        'scheduled_service_${scheduled.status.name}',
      if (!scheduled.hasCompleteDirectionData) 'incomplete_direction_data',
      if (scheduled.incompleteTripIds.isNotEmpty) 'incomplete_trip_data',
      if (evidence.operational.peakOperationSummary.hasLimitedCoverage)
        'limited_peak_operation_coverage',
      if (!evidence.operational.peakOperationSummary.hasReliablePeak)
        'peak_operation_not_reliable',
      if (evidence.operational.routePerformanceSummary.completeTrips.isEmpty)
        'insufficient_complete_route_performance_trips',
      if (evidence.feedback.totalRecordCount == 0)
        'zero_feedback_does_not_confirm_no_service_problem',
    ];

    return BusFrequencyGeminiEvidencePayload({
      'payload_type': 'bus_frequency_evidence',
      'route': _route(evidence.operational.route),
      'analysis_period': _period(evidence.periodStart, evidence.periodEnd),
      'scheduled_service': {
        'evidence_ref': 'scheduled.summary',
        'status': scheduled.status.name,
        'scheduled_departure_count': scheduled.scheduledDepartureCount,
        'has_complete_direction_data': scheduled.hasCompleteDirectionData,
        'direction_groups': directions,
        'incomplete_trip_ids': scheduled.incompleteTripIds
            .take(maxPayloadIncompleteTripIds)
            .toList(growable: false),
        'omitted_incomplete_trip_id_count':
            (scheduled.incompleteTripIds.length - maxPayloadIncompleteTripIds)
                .clamp(0, scheduled.incompleteTripIds.length),
        'omitted_direction_group_count':
            (scheduled.directionGroups.length - maxPayloadDirectionGroups)
                .clamp(0, scheduled.directionGroups.length),
      },
      'operational': _operational(evidence.operational),
      'feedback': {
        'total_record_count': evidence.feedback.totalRecordCount,
        'frequency_relevant_record_count':
            evidence.feedback.frequencyRelevantRecordCount,
        'counts': [
          _feedbackCount(
            'feedback.bus_was_late',
            BusFrequencyFeedbackIssueTypes.busWasLate,
            issueCounts,
          ),
          _feedbackCount(
            'feedback.bus_overcrowded',
            BusFrequencyFeedbackIssueTypes.busOvercrowded,
            issueCounts,
          ),
          _feedbackCount(
            'feedback.bus_did_not_arrive',
            BusFrequencyFeedbackIssueTypes.busDidNotArrive,
            issueCounts,
          ),
        ],
        'comments_included': false,
      },
      'known_limitations': limitations,
      'evidence_references': references.toList()..sort(),
    });
  }
}

class RouteStopGeminiPayloadBuilder {
  const RouteStopGeminiPayloadBuilder();

  RouteStopGeminiEvidencePayload build(DistrictRouteStopEvidence evidence) {
    final source = evidence.routeStopEvidence;
    final includedTrips = source.network.trips
        .take(maxPayloadTripVariants)
        .toList(growable: false);
    final references = <String>{
      'boundary.johor_bahru_district',
      'operational.peak_operation',
      'operational.route_performance',
      'feedback.missing_bus_stop',
      'feedback.long_walking_distance',
      'feedback.incorrect_route_information',
    };
    final tripPayloads = <Map<String, dynamic>>[];
    for (var tripIndex = 0; tripIndex < includedTrips.length; tripIndex++) {
      final trip = includedTrips[tripIndex];
      final tripReference = 'network.trip.$tripIndex';
      references.add(tripReference);
      final memberships =
          tripIndex < evidence.tripStopMembership.length &&
              evidence.tripStopMembership[tripIndex].tripId == trip.tripId
          ? evidence.tripStopMembership[tripIndex].stops
          : const <DistrictStopEvidence>[];
      final spacing = source.stopSpacingByTrip
          .where((item) => item.tripId == trip.tripId)
          .firstOrNull;
      final stops = <Map<String, dynamic>>[];
      for (final stop in trip.stops.take(maxPayloadStopsPerTrip)) {
        final membership = memberships
            .where(
              (item) =>
                  item.stopId == stop.stopId &&
                  item.stopSequence == stop.stopSequence,
            )
            .firstOrNull;
        final stopReference = 'stop.${Uri.encodeComponent(stop.stopId)}';
        references.add(stopReference);
        stops.add({
          'evidence_ref': stopReference,
          'stop_id': stop.stopId,
          'stop_name': stop.stopName,
          'stop_sequence': stop.stopSequence,
          'latitude': _finite(stop.coordinate?.latitude),
          'longitude': _finite(stop.coordinate?.longitude),
          'coordinate_available': stop.coordinate != null,
          'district_membership':
              (membership?.membership ?? DistrictStopMembership.unverifiable)
                  .name,
          'scheduled_arrival_seconds': stop.scheduledArrivalSeconds,
          'scheduled_departure_seconds': stop.scheduledDepartureSeconds,
        });
      }
      tripPayloads.add({
        'evidence_ref': tripReference,
        'trip_id': trip.tripId,
        'shape_id': trip.shapeId,
        'route_distance_meters': _finite(trip.routeDistanceMeters),
        'shape_coordinate_count': trip.shapePoints.length,
        'shape_coordinates_included': false,
        'stops': stops,
        'omitted_stop_count': (trip.stops.length - maxPayloadStopsPerTrip)
            .clamp(0, trip.stops.length),
        'consecutive_stop_spacing':
            spacing?.consecutiveStops
                .take(maxPayloadStopsPerTrip)
                .map(
                  (item) => {
                    'from_stop_id': item.fromStopId,
                    'from_stop_sequence': item.fromStopSequence,
                    'to_stop_id': item.toStopId,
                    'to_stop_sequence': item.toStopSequence,
                    'distance_meters': _finite(item.distanceMeters),
                  },
                )
                .toList(growable: false) ??
            const <Map<String, dynamic>>[],
      });
    }
    final issueCounts = source.feedback.countByIssueType;
    final missingCoordinateCount = source.network.trips.fold<int>(
      0,
      (total, trip) =>
          total + trip.stops.where((stop) => stop.coordinate == null).length,
    );
    final limitations = <String>[
      if (!evidence.boundary.isAvailable) 'district_boundary_unavailable',
      if (missingCoordinateCount > 0) 'missing_stop_coordinates',
      if (source.network.trips.any((trip) => trip.shapeId == null))
        'missing_shape_identity',
      if (source.network.trips.any((trip) => trip.routeDistanceMeters == null))
        'missing_route_geometry_distance',
      if (source.operational.peakOperationSummary.hasLimitedCoverage)
        'limited_peak_operation_coverage',
      if (source.operational.routePerformanceSummary.completeTrips.isEmpty)
        'insufficient_complete_route_performance_trips',
      if (source.feedback.totalRecordCount == 0)
        'zero_feedback_does_not_confirm_no_route_or_stop_problem',
    ];

    return RouteStopGeminiEvidencePayload({
      'payload_type': 'route_stop_evidence',
      'route': _route(source.network.route),
      'analysis_period': _period(source.periodStart, source.periodEnd),
      'district_boundary': {
        'evidence_ref': 'boundary.johor_bahru_district',
        'status': evidence.boundary.status.name,
        'custodian': evidence.boundary.source.custodian,
        'dataset': evidence.boundary.source.dataset,
        'layer': evidence.boundary.source.layer,
        'reference_date': evidence.boundary.source.referenceDate,
        'polygon_included': false,
        'stop_occurrence_counts': _membershipCounts(
          evidence.stopOccurrenceCounts,
        ),
        'unique_stop_counts': _membershipCounts(evidence.uniqueStopCounts),
      },
      'network': {
        'trip_variant_count': source.network.trips.length,
        'trip_variants': tripPayloads,
        'omitted_trip_variant_count':
            (source.network.trips.length - maxPayloadTripVariants).clamp(
              0,
              source.network.trips.length,
            ),
        'missing_coordinate_occurrence_count': missingCoordinateCount,
      },
      'operational': _operational(source.operational),
      'feedback': {
        'total_record_count': source.feedback.totalRecordCount,
        'route_stop_relevant_record_count':
            source.feedback.routeStopRelevantRecordCount,
        'counts': [
          _feedbackCount(
            'feedback.missing_bus_stop',
            RouteStopFeedbackIssueTypes.missingBusStop,
            issueCounts,
          ),
          _feedbackCount(
            'feedback.long_walking_distance',
            RouteStopFeedbackIssueTypes.longWalkingDistance,
            issueCounts,
          ),
          _feedbackCount(
            'feedback.incorrect_route_information',
            RouteStopFeedbackIssueTypes.incorrectRouteInformation,
            issueCounts,
          ),
        ],
        'comments_included': false,
      },
      'known_limitations': limitations,
      'evidence_references': references.toList()..sort(),
    });
  }
}

class CostGeminiPayloadBuilder {
  const CostGeminiPayloadBuilder();

  CostGeminiEvidencePayload build(FuelCostCalculationEvidence evidence) {
    final references = <String>{
      'cost.diesel_price',
      'cost.fuel_consumption_benchmark',
      'cost.scheduled_vehicle_km',
      'cost.fuel_range',
    };
    final directions = <Map<String, dynamic>>[];
    for (
      var index = 0;
      index < evidence.directionGroups.length &&
          index < maxPayloadDirectionGroups;
      index++
    ) {
      final group = evidence.directionGroups[index];
      final reference = 'cost.direction.$index';
      references.add(reference);
      directions.add({
        'evidence_ref': reference,
        'direction_id': group.directionId,
        'scheduled_departure_count': group.departures.length,
        'costable_departure_count': group.costableDepartureCount,
      });
    }
    final uncostable = evidence.uncostableDepartures
        .take(maxPayloadUncostableDepartures)
        .map(
          (item) => {
            'trip_id': item.departure.tripId,
            'direction_id': evidence.directionGroups
                .where((group) => group.departures.contains(item))
                .firstOrNull
                ?.directionId,
            'distance_status': item.distanceStatus.name,
          },
        )
        .toList(growable: false);
    final limitations = <String>[
      evidence.benchmark.limitation,
      if (!evidence.dieselPrice.isAvailable) 'diesel_price_unavailable',
      if (evidence.totalScheduledDepartureCount == 0) 'no_scheduled_departures',
      if (evidence.costableScheduledDepartureCount == 0)
        'no_costable_departures',
      if (evidence.uncostableDepartures.isNotEmpty)
        'some_departures_are_uncostable',
      if (evidence.scheduledServiceStatus !=
          ScheduledServiceEvidenceStatus.available)
        'scheduled_service_${evidence.scheduledServiceStatus.name}',
      if (!evidence.hasCompleteDirectionData) 'incomplete_direction_data',
    ];

    return CostGeminiEvidencePayload({
      'payload_type': 'cost_estimation_evidence',
      'route': _route(evidence.route),
      'analysis_period': _period(evidence.periodStart, evidence.periodEnd),
      'reference_date': _date(evidence.referenceDate),
      'calculation_status': evidence.status.name,
      'scheduled_service_status': evidence.scheduledServiceStatus.name,
      'has_complete_direction_data': evidence.hasCompleteDirectionData,
      'incomplete_trip_ids': evidence.incompleteTripIds
          .take(maxPayloadIncompleteTripIds)
          .toList(growable: false),
      'diesel_price': {
        'evidence_ref': 'cost.diesel_price',
        'status': evidence.dieselPrice.status.name,
        'rm_per_litre': _finite(evidence.dieselPrice.rmPerLitre),
        'effective_date': evidence.dieselPrice.effectiveDate == null
            ? null
            : _date(evidence.dieselPrice.effectiveDate!),
        'source': {
          'platform': evidence.dieselPrice.source.platform,
          'publisher': evidence.dieselPrice.source.publisher,
          'dataset_id': evidence.dieselPrice.source.datasetId,
          'dataset_name': evidence.dieselPrice.source.datasetName,
        },
      },
      'fuel_consumption_benchmark': {
        'evidence_ref': 'cost.fuel_consumption_benchmark',
        'low_litres_per_kilometre': _finite(
          evidence.benchmark.lowLitresPerKilometre,
        ),
        'high_litres_per_kilometre': _finite(
          evidence.benchmark.highLitresPerKilometre,
        ),
        'source': evidence.benchmark.source,
        'context': evidence.benchmark.context,
        'limitation': evidence.benchmark.limitation,
      },
      'scheduled_service': {
        'total_departure_count': evidence.totalScheduledDepartureCount,
        'costable_departure_count': evidence.costableScheduledDepartureCount,
        'uncostable_departure_count': evidence.uncostableDepartures.length,
        'directions': directions,
        'uncostable_departures': uncostable,
        'omitted_uncostable_departure_count':
            (evidence.uncostableDepartures.length -
                    maxPayloadUncostableDepartures)
                .clamp(0, evidence.uncostableDepartures.length),
      },
      'fuel_estimate': {
        'vehicle_km_evidence_ref': 'cost.scheduled_vehicle_km',
        'fuel_range_evidence_ref': 'cost.fuel_range',
        'scheduled_vehicle_kilometres': _finite(
          evidence.scheduledVehicleKilometres,
        ),
        'low_estimated_litres': _finite(evidence.lowEstimatedLitres),
        'high_estimated_litres': _finite(evidence.highEstimatedLitres),
        'low_estimated_fuel_expenditure_rm': _finite(
          evidence.lowEstimatedFuelCostRm,
        ),
        'high_estimated_fuel_expenditure_rm': _finite(
          evidence.highEstimatedFuelCostRm,
        ),
      },
      'unavailable_cost_categories': const [
        'driver_staff_cost',
        'maintenance_cost',
        'bus_acquisition_cost',
        'bus_stop_construction_cost',
        'total_implementation_cost',
      ],
      'known_limitations': limitations,
      'evidence_references': references.toList()..sort(),
    });
  }
}

Map<String, dynamic> _route(RoutePerformanceRoute route) => {
  'route_id': route.routeId,
  'short_name': route.shortName,
  'long_name': route.longName,
  'display_name': route.displayName,
};

Map<String, dynamic> _period(DateTime start, DateTime end) => {
  'start_utc': start.toUtc().toIso8601String(),
  'end_exclusive_utc': end.toUtc().toIso8601String(),
};

Map<String, dynamic> _operational(AiOperationalEvidence evidence) {
  final peak = evidence.peakOperationSummary;
  final performance = evidence.routePerformanceSummary;
  final coverageCounts = <String, int>{
    for (final status in TripCoverageStatus.values) status.name: 0,
  };
  for (final trip in performance.trips) {
    coverageCounts[trip.coverageStatus.name] =
        coverageCounts[trip.coverageStatus.name]! + 1;
  }
  return {
    'peak_operation': {
      'evidence_ref': 'operational.peak_operation',
      'observation_count': peak.observationCount,
      'distinct_trip_occurrences': peak.distinctTripOccurrences,
      'observed_day_count': peak.observedDayCount,
      'routes_represented': peak.routesRepresented,
      'average_activity': _finite(peak.averageActivity),
      'activity_difference_percent': _finite(peak.activityDifferencePercent),
      'has_reliable_peak': peak.hasReliablePeak,
      'has_limited_coverage': peak.hasLimitedCoverage,
      'observed_window_start': peak.observedWindowStart
          ?.toUtc()
          .toIso8601String(),
      'observed_window_end': peak.observedWindowEnd?.toUtc().toIso8601String(),
      'peak_buckets': peak.peakBuckets
          .take(maxPayloadPeakBuckets)
          .map(
            (bucket) => {
              'start_minute': bucket.startMinute,
              'average_active_trips': _finite(bucket.averageActiveTrips),
              'activity_level': bucket.level.name,
            },
          )
          .toList(growable: false),
      'omitted_peak_bucket_count':
          (peak.peakBuckets.length - maxPayloadPeakBuckets).clamp(
            0,
            peak.peakBuckets.length,
          ),
    },
    'route_performance': {
      'evidence_ref': 'operational.route_performance',
      'historical_trip_count': performance.trips.length,
      'complete_trip_count': performance.completeTrips.length,
      'partial_trip_count': performance.partialTripCount,
      'coverage_counts': coverageCounts,
      'total_observations': performance.totalObservations,
      'average_observed_travel_time_seconds':
          performance.averageTravelTime?.inSeconds,
      'delayed_trip_count': performance.delayedTripCount,
      'delay_frequency_percent': _finite(performance.delayFrequencyPercent),
      'schedule_adherence_percent': _finite(
        performance.scheduleAdherencePercent,
      ),
    },
  };
}

Map<String, dynamic> _feedbackCount(
  String reference,
  String issueType,
  Map<String, int> counts,
) => {
  'evidence_ref': reference,
  'issue_type': issueType,
  'record_count': counts[issueType] ?? 0,
};

Map<String, dynamic> _membershipCounts(DistrictMembershipCounts counts) => {
  'inside_johor_bahru_district': counts.insideJohorBahruDistrict,
  'outside_johor_bahru_district': counts.outsideJohorBahruDistrict,
  'unverifiable': counts.unverifiable,
  'total': counts.total,
};

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

double? _finite(num? value) {
  if (value == null) return null;
  final result = value.toDouble();
  return result.isFinite ? result : null;
}
