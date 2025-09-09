import 'package:cloud_firestore/cloud_firestore.dart';
class MessageModel {
  final String id;
  final String senderId;
  final String senderName;
  final String senderRole;
  final String content;
  final DateTime timestamp;
  final String regionId;
  final String? driverId;
  final bool isRead;
  final bool isUrgent;
  final String? type;
  final int? expireAfterHours;
  MessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.content,
    required this.timestamp,
    required this.regionId,
    this.driverId,
    this.isRead = false,
    this.isUrgent = false,
    this.type,
    this.expireAfterHours,
  });
  factory MessageModel.fromMap(String id, Map<String, dynamic> data) {
    return MessageModel(
      id: id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      senderRole: data['senderRole'] ?? '',
      content: data['content'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      regionId: data['regionId'] ?? '',
      driverId: data['driverId'],
      isRead: data['isRead'] ?? false,
      isUrgent: data['isUrgent'] ?? false,
      type: data['type'],
      expireAfterHours: (data['expireAfterHours'] as int?),
    );
  }
  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'content': content,
      'timestamp': Timestamp.fromDate(timestamp),
      'regionId': regionId,
      'driverId': driverId,
      'isRead': isRead,
      'isUrgent': isUrgent,
      'type': type ?? 'chat',
      if (expireAfterHours != null) 'expireAfterHours': expireAfterHours,
    };
  }
  MessageModel copyWith({
    bool? isRead,
    bool? isUrgent,
    int? expireAfterHours,
  }) {
    return MessageModel(
      id: id,
      senderId: senderId,
      senderName: senderName,
      senderRole: senderRole,
      content: content,
      timestamp: timestamp,
      regionId: regionId,
      driverId: driverId,
      isRead: isRead ?? this.isRead,
      isUrgent: isUrgent ?? this.isUrgent,
      type: type,
      expireAfterHours: expireAfterHours ?? this.expireAfterHours,
    );
  }
}

// Updated


// Updated Again

