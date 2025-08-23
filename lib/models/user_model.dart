import 'package:cloud_firestore/cloud_firestore.dart';
class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String? regionId;
  final String? driverId;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? profileImageUrl;
  final Map<String, dynamic>? additionalData;
  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.regionId,
    this.driverId,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.profileImageUrl,
    this.additionalData,
  });
  factory UserModel.fromMap(Map<String, dynamic> data, String id) {
    return UserModel(
      id: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      role: data['role'] ?? '',
      regionId: data['regionId'],
      driverId: data['driverId'],
      isActive: data['isActive'] ?? true,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      profileImageUrl: data['profileImageUrl'],
      additionalData: data['additionalData'] as Map<String, dynamic>?,
    );
  }
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel.fromMap(data, doc.id);
  }
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'regionId': regionId,
      'driverId': driverId,
      'isActive': isActive,
      'createdAt': createdAt != null 
          ? Timestamp.fromDate(createdAt!) 
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'profileImageUrl': profileImageUrl,
      'additionalData': additionalData,
    };
  }
  UserModel copyWith({
    String? name,
    String? email,
    String? phone,
    String? role,
    String? regionId,
    String? driverId,
    bool? isActive,
    DateTime? updatedAt,
    String? profileImageUrl,
    Map<String, dynamic>? additionalData,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      regionId: regionId ?? this.regionId,
      driverId: driverId ?? this.driverId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      additionalData: additionalData ?? this.additionalData,
    );
  }
  bool get isAdmin => role == 'Admin';
  bool get isDriver => role == 'Şoför';
  bool get isPassenger => role == 'Yolcu';
  bool get isUserActive => isActive;
  bool get hasRegion => regionId != null && regionId!.isNotEmpty;
  bool get hasDriver => driverId != null && driverId!.isNotEmpty;
  @override
  String toString() {
    return 'UserModel(id: $id, name: $name, email: $email, role: $role, regionId: $regionId, isActive: $isActive)';
  }
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel && other.id == id;
  }
  @override
  int get hashCode => id.hashCode;
}
