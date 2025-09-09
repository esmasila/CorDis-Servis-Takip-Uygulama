import 'package:cloud_firestore/cloud_firestore.dart';
enum PermissionType {
  morningToday,
  eveningToday,
  morningTomorrow,
  allToday,
  allTomorrow,
  vacation,
}
class PermissionModel {
  final String id;
  final String userId;
  final String userName;
  final PermissionType type;
  final DateTime startDate;
  final DateTime? endDate;
  final String? reason;
  final bool isActive;
  final DateTime createdAt;
  final String? driverId;
  PermissionModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.type,
    required this.startDate,
    this.endDate,
    this.reason,
    this.isActive = true,
    required this.createdAt,
    this.driverId,
  });
  factory PermissionModel.fromMap(String id, Map<String, dynamic> data) {
    return PermissionModel(
      id: id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      type: PermissionType.values.firstWhere(
        (e) => e.toString() == data['type'],
        orElse: () => PermissionType.allToday,
      ),
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: data['endDate'] != null
          ? (data['endDate'] as Timestamp).toDate()
          : null,
      reason: data['reason'],
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      driverId: data['driverId'],
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'type': type.toString(),
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'reason': reason,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'driverId': driverId,
    };
  }
  String get typeDisplayName {
    switch (type) {
      case PermissionType.morningToday:
        return 'Bugün sabah yokum';
      case PermissionType.eveningToday:
        return 'Bugün akşam yokum';
      case PermissionType.morningTomorrow:
        return 'Yarın sabah yokum';
      case PermissionType.allToday:
        return 'Bugün gelmeyeceğim';
      case PermissionType.allTomorrow:
        return 'Yarın gelmeyeceğim';
      case PermissionType.vacation:
        return 'Tatil';
    }
  }
  String? get description => reason;
  bool isValidForDate(DateTime date) {
    if (!isActive) return false;
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    switch (type) {
      case PermissionType.morningToday:
      case PermissionType.eveningToday:
      case PermissionType.allToday:
        return _isSameDay(date, today);
      case PermissionType.morningTomorrow:
      case PermissionType.allTomorrow:
        return _isSameDay(date, tomorrow);
      case PermissionType.vacation:
        return date.isAfter(startDate.subtract(const Duration(days: 1))) &&
               (endDate == null || date.isBefore(endDate!.add(const Duration(days: 1))));
    }
  }
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }
}



 Again


