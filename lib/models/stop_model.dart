import 'package:cloud_firestore/cloud_firestore.dart';
class StopModel {
  final String id;
  final String driverId;
  final String? passengerId;
  final String? passengerName;
  final String address;
  final double lat;
  final double lng;
  final DateTime date;
  final int order;
  final bool isCompleted;
  final String status;
  final DateTime? completedAt;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? phoneNumber;
  final String? regionId;
  final String? serviceType;
  final Map<String, dynamic>? metadata;
  final List<String>? passengerIds;
  String get name => passengerName ?? address;
  DateTime? get arrivedTime => completedAt;
  int? get waitDuration {
    if (completedAt != null && createdAt != null) {
      return completedAt!.difference(createdAt).inSeconds;
    }
    return null;
  }
  int get passengerCount => passengerIds?.length ?? 1;
  StopModel({
    required this.id,
    required this.driverId,
    this.passengerId,
    this.passengerName,
    required this.address,
    required this.lat,
    required this.lng,
    required this.date,
    required this.order,
    this.isCompleted = false,
    this.status = 'pending',
    this.completedAt,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.phoneNumber,
    this.regionId,
    this.serviceType,
    this.metadata,
    this.passengerIds,
  });
  factory StopModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StopModel(
      id: doc.id,
      driverId: data['driverId'] ?? '',
      passengerId: data['passengerId'],
      passengerName: data['passengerName'],
      address: data['address'] ?? '',
      lat: (data['lat'] ?? 0.0).toDouble(),
      lng: (data['lng'] ?? 0.0).toDouble(),
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      order: data['order'] ?? 0,
      isCompleted: data['isCompleted'] ?? false,
      status: data['status'] ?? 'pending',
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      note: data['note'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      phoneNumber: data['phoneNumber'],
      regionId: data['regionId'],
      serviceType: data['serviceType'],
      metadata: data['metadata'] as Map<String, dynamic>?,
      passengerIds: data['passengerIds'] != null ? List<String>.from(data['passengerIds']) : null,
    );
  }
  factory StopModel.fromMap(Map<String, dynamic> map, String id) {
    return StopModel(
      id: id,
      driverId: map['driverId'] ?? '',
      passengerId: map['passengerId'],
      passengerName: map['passengerName'],
      address: map['address'] ?? '',
      lat: (map['lat'] ?? 0.0).toDouble(),
      lng: (map['lng'] ?? 0.0).toDouble(),
      date: map['date'] is Timestamp 
          ? (map['date'] as Timestamp).toDate() 
          : DateTime.parse(map['date'] ?? DateTime.now().toIso8601String()),
      order: map['order'] ?? 0,
      isCompleted: map['isCompleted'] ?? false,
      status: map['status'] ?? 'pending',
      completedAt: map['completedAt'] is Timestamp 
          ? (map['completedAt'] as Timestamp).toDate() 
          : (map['completedAt'] != null ? DateTime.parse(map['completedAt']) : null),
      note: map['note'],
      createdAt: map['createdAt'] is Timestamp 
          ? (map['createdAt'] as Timestamp).toDate() 
          : DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: map['updatedAt'] is Timestamp 
          ? (map['updatedAt'] as Timestamp).toDate() 
          : DateTime.parse(map['updatedAt'] ?? DateTime.now().toIso8601String()),
      phoneNumber: map['phoneNumber'],
      regionId: map['regionId'],
      serviceType: map['serviceType'],
      metadata: map['metadata'] as Map<String, dynamic>?,
      passengerIds: map['passengerIds'] != null ? List<String>.from(map['passengerIds']) : null,
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'driverId': driverId,
      'passengerId': passengerId,
      'passengerName': passengerName,
      'address': address,
      'lat': lat,
      'lng': lng,
      'date': Timestamp.fromDate(date),
      'order': order,
      'isCompleted': isCompleted,
      'status': status,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'note': note,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'phoneNumber': phoneNumber,
      'regionId': regionId,
      'serviceType': serviceType,
      'metadata': metadata,
      'passengerIds': passengerIds,
    };
  }
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driverId': driverId,
      'passengerId': passengerId,
      'passengerName': passengerName,
      'address': address,
      'lat': lat,
      'lng': lng,
      'date': date.toIso8601String(),
      'order': order,
      'isCompleted': isCompleted,
      'status': status,
      'completedAt': completedAt?.toIso8601String(),
      'note': note,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'phoneNumber': phoneNumber,
      'regionId': regionId,
      'serviceType': serviceType,
      'metadata': metadata,
      'passengerIds': passengerIds,
    };
  }
  factory StopModel.fromJson(Map<String, dynamic> json) {
    return StopModel(
      id: json['id'] ?? '',
      driverId: json['driverId'] ?? '',
      passengerId: json['passengerId'],
      passengerName: json['passengerName'],
      address: json['address'] ?? '',
      lat: (json['lat'] ?? 0.0).toDouble(),
      lng: (json['lng'] ?? 0.0).toDouble(),
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
      order: json['order'] ?? 0,
      isCompleted: json['isCompleted'] ?? false,
      status: json['status'] ?? 'pending',
      completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
      note: json['note'],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
      phoneNumber: json['phoneNumber'],
      regionId: json['regionId'],
      serviceType: json['serviceType'],
      metadata: json['metadata'] as Map<String, dynamic>?,
      passengerIds: json['passengerIds'] != null ? List<String>.from(json['passengerIds']) : null,
    );
  }
  StopModel copyWith({
    String? id,
    String? driverId,
    String? passengerId,
    String? passengerName,
    String? address,
    double? lat,
    double? lng,
    DateTime? date,
    int? order,
    bool? isCompleted,
    String? status,
    DateTime? completedAt,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? phoneNumber,
    String? regionId,
    String? serviceType,
    Map<String, dynamic>? metadata,
    List<String>? passengerIds,
  }) {
    return StopModel(
      id: id ?? this.id,
      driverId: driverId ?? this.driverId,
      passengerId: passengerId ?? this.passengerId,
      passengerName: passengerName ?? this.passengerName,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      date: date ?? this.date,
      order: order ?? this.order,
      isCompleted: isCompleted ?? this.isCompleted,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      regionId: regionId ?? this.regionId,
      serviceType: serviceType ?? this.serviceType,
      metadata: metadata ?? this.metadata,
      passengerIds: passengerIds ?? this.passengerIds,
    );
  }
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StopModel && other.id == id;
  }
  @override
  int get hashCode => id.hashCode;
  @override
  String toString() {
    return 'StopModel(id: $id, passengerName: $passengerName, address: $address, isCompleted: $isCompleted, status: $status)';
  }
  bool get isPending => status == 'pending';
  bool get isInProgress => status == 'in_progress';
  bool get isSkipped => status == 'skipped';
  bool get isMorningService => serviceType == 'morning';
  bool get isEveningService => serviceType == 'evening';
  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year && 
           date.month == now.month && 
           date.day == now.day;
  }
  bool get isPast {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final stopDate = DateTime(date.year, date.month, date.day);
    return stopDate.isBefore(today);
  }
  bool get isFuture {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final stopDate = DateTime(date.year, date.month, date.day);
    return stopDate.isAfter(today);
  }
  Duration? get completionDuration {
    if (completedAt == null) return null;
    return completedAt!.difference(date);
  }
  int get priority {
    if (isCompleted) return 1000 + order;
    if (isInProgress) return order;
    return 100 + order;
  }
}

// Updated

