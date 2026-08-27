import 'package:government_transit_collector/features/journey_map/data/journey_map_models.dart';

enum DistrictBoundaryStatus { available, unavailable, unusable }

class DistrictBoundaryEvidence {
  const DistrictBoundaryEvidence({
    required this.status,
    required this.geometry,
    required this.source,
  });

  final DistrictBoundaryStatus status;
  final DistrictBoundaryGeometry? geometry;
  final DistrictBoundarySource source;

  bool get isAvailable =>
      status == DistrictBoundaryStatus.available && geometry != null;
}

class DistrictBoundarySource {
  const DistrictBoundarySource({
    required this.custodian,
    required this.dataset,
    required this.layer,
    required this.referenceDate,
  });

  final String custodian;
  final String dataset;
  final String layer;
  final String referenceDate;
}

class DistrictBoundaryGeometry {
  const DistrictBoundaryGeometry({required this.polygons});

  final List<DistrictBoundaryPolygon> polygons;
}

class DistrictBoundaryPolygon {
  const DistrictBoundaryPolygon({required this.exterior, required this.holes});

  final List<MapCoordinate> exterior;
  final List<List<MapCoordinate>> holes;
}

const johorBahruDistrictBoundarySource = DistrictBoundarySource(
  custodian: 'JUPEM',
  dataset: 'District or Jajahan Coverage Administrative',
  layer: 'MyGeomap/Msia_Coverage/MapServer/2',
  referenceDate: 'August 2019',
);
