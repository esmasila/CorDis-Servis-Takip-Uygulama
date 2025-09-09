import 'package:cloud_firestore/cloud_firestore.dart';
class DriverModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String vehiclePlate;
  final String regionId;
  final bool isActive;
  final double? currentLat;
  final double? currentLng;
  final DateTime? lastLocationUpdate;
  final bool isOnDuty;
  final DateTime? createdAt;
  DriverModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.vehiclePlate,
    required this.regionId,
    this.isActive = true,
    this.currentLat,
    this.currentLng,
    this.lastLocationUpdate,
    this.isOnDuty = false,
    this.createdAt,
  });
  factory DriverModel.fromMap(String id, Map<String, dynamic> data) {
    return DriverModel(
      id: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      vehiclePlate: data['vehiclePlate'] ?? '',
      regionId: data['regionId'] ?? '',
      isActive: data['isActive'] ?? true,
      currentLat: data['currentLat']?.toDouble(),
      currentLng: data['currentLng']?.toDouble(),
      lastLocationUpdate: data['lastLocationUpdate'] != null
          ? (data['lastLocationUpdate'] as Timestamp).toDate()
          : null,
      isOnDuty: data['isOnDuty'] ?? false,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
  factory DriverModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DriverModel.fromMap(doc.id, data);
  }
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'vehiclePlate': vehiclePlate,
      'regionId': regionId,
      'isActive': isActive,
      'currentLat': currentLat,
      'currentLng': currentLng,
      'lastLocationUpdate': lastLocationUpdate != null 
          ? Timestamp.fromDate(lastLocationUpdate!) 
          : null,
      'isOnDuty': isOnDuty,
      'createdAt': createdAt != null 
          ? Timestamp.fromDate(createdAt!) 
          : FieldValue.serverTimestamp(),
    };
  }
  DriverModel copyWith({
    String? name,
    String? email,
    String? phone,
    String? vehiclePlate,
    String? regionId,
    bool? isActive,
    double? currentLat,
    double? currentLng,
    DateTime? lastLocationUpdate,
    bool? isOnDuty,
  }) {
    return DriverModel(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      regionId: regionId ?? this.regionId,
      isActive: isActive ?? this.isActive,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      lastLocationUpdate: lastLocationUpdate ?? this.lastLocationUpdate,
      isOnDuty: isOnDuty ?? this.isOnDuty,
      createdAt: createdAt,
    );
  }
}



 Again


