import 'package:cloud_firestore/cloud_firestore.dart';
class StopLogModel {
  final String id;
  final String stopId;
  final String driverId;
  final String driverName;
  final String vehiclePlate;
  final String regionId;
  final String stopAddress;
  final double latitude;
  final double longitude;
  final DateTime arrivedAt;
  final DateTime? departedAt;
  final int passengerCount;
  final List<String> passengerIds;
  final List<String> passengerNames;
  final String status;
  final String? notes;
  final int? waitDurationSeconds;
  final DateTime createdAt;
  StopLogModel({
    required this.id,
    required this.stopId,
    required this.driverId,
    required this.driverName,
    required this.vehiclePlate,
    required this.regionId,
    required this.stopAddress,
    required this.latitude,
    required this.longitude,
    required this.arrivedAt,
    this.departedAt,
    required this.passengerCount,
    required this.passengerIds,
    required this.passengerNames,
    required this.status,
    this.notes,
    this.waitDurationSeconds,
    required this.createdAt,
  });
  factory StopLogModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StopLogModel(
      id: doc.id,
      stopId: data['stopId'] ?? '',
      driverId: data['driverId'] ?? '',
      driverName: data['driverName'] ?? '',
      vehiclePlate: data['vehiclePlate'] ?? '',
      regionId: data['regionId'] ?? '',
      stopAddress: data['stopAddress'] ?? '',
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      arrivedAt: (data['arrivedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      departedAt: (data['departedAt'] as Timestamp?)?.toDate(),
      passengerCount: data['passengerCount'] ?? 0,
      passengerIds: List<String>.from(data['passengerIds'] ?? []),
      passengerNames: List<String>.from(data['passengerNames'] ?? []),
      status: data['status'] ?? 'arrived',
      notes: data['notes'],
      waitDurationSeconds: data['waitDurationSeconds'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'stopId': stopId,
      'driverId': driverId,
      'driverName': driverName,
      'vehiclePlate': vehiclePlate,
      'regionId': regionId,
      'stopAddress': stopAddress,
      'latitude': latitude,
      'longitude': longitude,
      'arrivedAt': Timestamp.fromDate(arrivedAt),
      'departedAt': departedAt != null ? Timestamp.fromDate(departedAt!) : null,
      'passengerCount': passengerCount,
      'passengerIds': passengerIds,
      'passengerNames': passengerNames,
      'status': status,
      'notes': notes,
      'waitDurationSeconds': waitDurationSeconds,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
  StopLogModel copyWith({
    String? id,
    String? stopId,
    String? driverId,
    String? driverName,
    String? vehiclePlate,
    String? regionId,
    String? stopAddress,
    double? latitude,
    double? longitude,
    DateTime? arrivedAt,
    DateTime? departedAt,
    int? passengerCount,
    List<String>? passengerIds,
    List<String>? passengerNames,
    String? status,
    String? notes,
    int? waitDurationSeconds,
    DateTime? createdAt,
  }) {
    return StopLogModel(
      id: id ?? this.id,
      stopId: stopId ?? this.stopId,
      driverId: driverId ?? this.driverId,
      driverName: driverName ?? this.driverName,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      regionId: regionId ?? this.regionId,
      stopAddress: stopAddress ?? this.stopAddress,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      departedAt: departedAt ?? this.departedAt,
      passengerCount: passengerCount ?? this.passengerCount,
      passengerIds: passengerIds ?? this.passengerIds,
      passengerNames: passengerNames ?? this.passengerNames,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      waitDurationSeconds: waitDurationSeconds ?? this.waitDurationSeconds,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

// Updated


// Updated Again

