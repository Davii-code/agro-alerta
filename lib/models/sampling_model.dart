import 'package:hive/hive.dart';

part 'sampling_model.g.dart';

@HiveType(typeId: 1)
class SamplingModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String fieldId;

  @HiveField(2)
  final String observerId;

  @HiveField(3)
  final String species;

  @HiveField(4)
  final int count;

  @HiveField(5)
  final String unit;

  @HiveField(6)
  final String method;

  @HiveField(7)
  final double latitude;

  @HiveField(8)
  final double longitude;

  @HiveField(9)
  final DateTime createdAt;

  @HiveField(10)
  bool isSynced; // Local sync flag: false if pending, true if synced to Supabase

  SamplingModel({
    required this.id,
    required this.fieldId,
    required this.observerId,
    required this.species,
    required this.count,
    required this.unit,
    required this.method,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.isSynced = false,
  });

  factory SamplingModel.fromJson(Map<String, dynamic> json) {
    double lat = 0.0;
    double lon = 0.0;
    if (json['location'] != null) {
      if (json['location'] is Map) {
        final coordinates = json['location']['coordinates'] as List?;
        if (coordinates != null && coordinates.length >= 2) {
          lon = (coordinates[0] as num).toDouble();
          lat = (coordinates[1] as num).toDouble();
        }
      }
    }
    return SamplingModel(
      id: json['id'] as String,
      fieldId: json['field_id'] as String,
      observerId: json['observer_id'] as String,
      species: json['species'] as String,
      count: json['count'] as int,
      unit: json['unit'] as String,
      method: json['method'] as String,
      latitude: lat,
      longitude: lon,
      createdAt: DateTime.parse(json['created_at'] as String),
      isSynced: true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'field_id': fieldId,
      'observer_id': observerId,
      'species': species,
      'count': count,
      'unit': unit,
      'method': method,
      'location': 'POINT($longitude $latitude)', // WKT geography format
      'created_at': createdAt.toIso8601String(),
    };
  }
}
