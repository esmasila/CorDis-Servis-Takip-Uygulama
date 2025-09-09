import 'package:cloud_firestore/cloud_firestore.dart';
class RegionModel {
  final String id;
  final String name;
  final String description;
  final bool isActive;
  final DateTime createdAt;
  final List<String> driverIds;
  final int passengerCount;
  RegionModel({
    required this.id,
    required this.name,
    required this.description,
    this.isActive = true,
    required this.createdAt,
    this.driverIds = const [],
    this.passengerCount = 0,
  });
  factory RegionModel.fromMap(String id, Map<String, dynamic> data) {
    return RegionModel(
      id: id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      isActive: data['isActive'] ?? true,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      driverIds: List<String>.from(data['driverIds'] ?? []),
      passengerCount: data['passengerCount'] ?? 0,
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'driverIds': driverIds,
      'passengerCount': passengerCount,
    };
  }
  RegionModel copyWith({
    String? name,
    String? description,
    bool? isActive,
    List<String>? driverIds,
    int? passengerCount,
  }) {
    return RegionModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      driverIds: driverIds ?? this.driverIds,
      passengerCount: passengerCount ?? this.passengerCount,
    );
  }
}

// Updated


// Updated Again

