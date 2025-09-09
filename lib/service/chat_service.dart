import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';
import 'dart:async';
class ChatService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Timer? _expiryCheckTimer;
  static bool _isExpiryServiceInitialized = false;
  static Future<void> initializeExpiryService() async {
    if (_isExpiryServiceInitialized) return;
    print('🕐 Süreli mesaj servisi başlatılıyor...');
    _expiryCheckTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _cleanupExpiredMessages();
    });
    _isExpiryServiceInitialized = true;
    print('✅ Süreli mesaj servisi başlatıldı');
  }
  static void disposeExpiryService() {
    _expiryCheckTimer?.cancel();
    _isExpiryServiceInitialized = false;
    print('🛑 Süreli mesaj servisi durduruldu');
  }
  static Future<void> _cleanupExpiredMessages() async {
    try {
      final now = DateTime.now();
      print('🧹 Süresi dolan mesajlar kontrol ediliyor...');
      final snapshot = await _firestore
          .collection('messages')
          .where('expireAfterHours', isGreaterThan: 0)
          .get();
      final expiredMessages = <DocumentSnapshot>[];
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = data['timestamp'] as Timestamp?;
        final expireAfterHours = data['expireAfterHours'] as int?;
        if (timestamp != null &&
            expireAfterHours != null &&
            expireAfterHours > 0) {
          final messageTime = timestamp.toDate();
          final expiryTime = messageTime.add(Duration(hours: expireAfterHours));
          if (now.isAfter(expiryTime)) {
            expiredMessages.add(doc);
          }
        }
      }
      if (expiredMessages.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in expiredMessages) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print('✅ ${expiredMessages.length} süresi dolan mesaj silindi');
      }
    } catch (e) {
      print('❌ Süresi dolan mesaj temizleme hatası: $e');
    }
  }
  static Future<String?> sendMessage({
    required String senderId,
    required String senderName,
    required String senderRole,
    required String content,
    required String regionId,
    String? driverId,
    bool isUrgent = false,
    String type = 'chat',
    int? expireAfterHours,
  }) async {
    try {
      print('[ChatService] Grup mesajı gönderiliyor:');
      print('- Gönderen: $senderName ($senderRole)');
      print('- İçerik: $content');
      print('- Bölge ID: $regionId');
      print('- Gönderen ID: $senderId');
      print('- Driver ID: ${driverId ?? "null"}');
      if (expireAfterHours != null && expireAfterHours > 0) {
        print('- Süre: $expireAfterHours saat sonra silinecek');
      }
      if (content.trim().isEmpty) {
        print('❌ Mesaj içeriği boş olamaz');
        return 'Mesaj içeriği boş olamaz';
      }
      if (regionId.trim().isEmpty) {
        print('❌ Bölge ID boş olamaz');
        return 'Bölge ID gerekli';
      }
      final message = MessageModel(
        id: '',
        senderId: senderId,
        senderName: senderName,
        senderRole: senderRole,
        content: content.trim(),
        timestamp: DateTime.now(),
        regionId: regionId,
        driverId: driverId,
        isUrgent: isUrgent,
        type: type,
        expireAfterHours: expireAfterHours,
      );
      final docRef =
          await _firestore.collection('messages').add(message.toMap());
      print('[ChatService] ✅ Grup mesajı başarıyla kaydedildi: ${docRef.id}');
      print('- Firestore doküman ID: ${docRef.id}');
      print('- Firebase Functions bildirim tetikleyicisi çalışacak');
      print(
          '- DriverId: ${driverId ?? "null"} (null olabilir, bildirim yine de gidecek)');
      print('- RegionId: $regionId');
      print('- SenderRole: $senderRole');
      print('- SenderId: $senderId');
      print('- SenderName: $senderName');
      print('🔍 Firebase Functions log\'larını kontrol edin...');
      print(
          '💡 DriverId null olsa bile bölgedeki tüm kullanıcılara bildirim gidecek');
      return null;
    } catch (e) {
      print('[ChatService] ❌ Grup mesajı gönderme hatası: $e');
      print('- Hata detayı: $e');
      return 'Mesaj gönderilirken hata: $e';
    }
  }
  static Stream<List<MessageModel>> getRegionMessages(
      String regionId, String? driverId) {
    print('[ChatService] Grup mesajları sorgulanıyor:');
    print('- Bölge ID: $regionId');
    print('- Driver ID: $driverId');
    print('- Grup chat modu: Sadece regionId ile filtreleme');
    try {
      return _firestore
          .collection('messages')
          .where('regionId', isEqualTo: regionId)
          .orderBy('timestamp',
              descending: false)
          .snapshots()
          .map((snapshot) {
        print('[ChatService] Firestore snapshot alındı:');
        print('- Connection state: ${snapshot.metadata.hasPendingWrites}');
        print('- Document count: ${snapshot.docs.length}');
        print('- Changes: ${snapshot.docChanges.length}');
        print('- Metadata: ${snapshot.metadata}');
        if (snapshot.docs.isNotEmpty) {
          print('- İlk mesaj örneği: ${snapshot.docs.first.data()}');
          print('- Son mesaj örneği: ${snapshot.docs.last.data()}');
        } else {
          print('⚠️ Hiç mesaj bulunamadı!');
          print(
              '🔍 Firestore sorgusu: messages koleksiyonu, regionId = $regionId');
        }
        final messages = _parseMessages(snapshot);
        print('[ChatService] Parse edilen mesaj sayısı: ${messages.length}');
        return messages;
      });
    } catch (e) {
      print('[ChatService] Grup mesajları sorgulama hatası: $e');
      print('❌ Hata detayı: $e');
      return Stream.value(<MessageModel>[]);
    }
  }
  static Future<void> clearOldMessages({
    required String regionId,
    required int expiryHours,
  }) async {
    try {
      final threshold = DateTime.now().subtract(Duration(hours: expiryHours));
      final query = await _firestore
          .collection('messages')
          .where('regionId', isEqualTo: regionId)
          .where('timestamp', isLessThan: Timestamp.fromDate(threshold))
          .get();
      final batch = _firestore.batch();
      for (final d in query.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      print('🧹 ${query.docs.length} eski mesaj temizlendi');
    } catch (e) {
      print('Eski mesajları temizleme hatası: $e');
    }
  }
  static Stream<List<MessageModel>> getUrgentMessagesForDriver(
      String driverId) {
    try {
      return _firestore
          .collection('messages')
          .where('driverId', isEqualTo: driverId)
          .where('isUrgent', isEqualTo: true)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots()
          .map((s) => _parseMessages(s));
    } catch (e) {
      print('Acil mesajlar sorgu hatası: $e');
      return Stream.value(<MessageModel>[]);
    }
  }
  static List<MessageModel> _parseMessages(QuerySnapshot snapshot) {
    final messages = <MessageModel>[];
    print(
        '[ChatService] _parseMessages başladı: ${snapshot.docs.length} doküman');
    for (var doc in snapshot.docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        print('Mesaj verisi: ${doc.id} -> $data');
        if (data['timestamp'] == null) {
          print('⚠️ Timestamp null: ${doc.id}');
          continue;
        }
        final message = MessageModel.fromMap(doc.id, data);
        messages.add(message);
        print(
            '✅ Mesaj parse edildi: ${message.senderName} - ${message.content}');
      } catch (e) {
        print('❌ Mesaj parse hatası (${doc.id}): $e');
        print('   Hatalı veri: ${doc.data()}');
      }
    }
    print('Parse edilen mesaj sayısı: ${messages.length}');
    return messages;
  }
  static Stream<List<MessageModel>> getMessagesForRegion(String regionId) {
    return _firestore
        .collection('messages')
        .where('regionId', isEqualTo: regionId)
        .snapshots()
        .map((snapshot) {
      print('Admin mesajları yüklendi: ${snapshot.docs.length} adet');
      final messages = _parseMessages(snapshot);
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return messages;
    });
  }
  static Future<void> markMessageAsRead(String messageId) async {
    try {
      await _firestore
          .collection('messages')
          .doc(messageId)
          .update({'isRead': true});
    } catch (e) {
      print('Mesaj okundu işaretleme hatası: $e');
    }
  }
  static Stream<int> getUnreadMessageCount(String userId, String regionId) {
    return _firestore
        .collection('messages')
        .where('regionId', isEqualTo: regionId)
        .where('senderId', isNotEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
  static Future<String?> sendMissedAlert({
    required String passengerId,
    required String passengerName,
    required String driverId,
    required String regionId,
  }) async {
    try {
      final alertMessage = MessageModel(
        id: '',
        senderId: passengerId,
        senderName: passengerName,
        senderRole: 'Yolcu',
        content: '🚨 BENİ KAÇIRDIN! Lütfen geri dön.',
        timestamp: DateTime.now(),
        regionId: regionId,
        driverId: driverId,
        isUrgent: true,
        type: 'missed_alert',
      );
      await _firestore.collection('messages').add(alertMessage.toMap());
      await _firestore.collection('missed_alerts').add({
        'passengerId': passengerId,
        'passengerName': passengerName,
        'driverId': driverId,
        'regionId': regionId,
        'timestamp': Timestamp.fromDate(DateTime.now()),
        'isResolved': false,
      });
      try {
        await _firestore.collection('driver_notifications').add({
          'driverId': driverId,
          'title': 'Acil Uyarı',
          'message': '🚨 ${passengerName} – Beni Kaçırdın!',
          'priority': 'high',
          'timestamp': Timestamp.fromDate(DateTime.now()),
          'isRead': false,
          'type': 'missed_alert',
          'senderId': passengerId,
          'senderRole': 'Yolcu',
        });
      } catch (e) {
        print('driver_notifications yazma hatası: $e');
      }
      return null;
    } catch (e) {
      print('Uyarı gönderme hatası: $e');
      return 'Uyarı gönderilirken hata: $e';
    }
  }
  static Future<List<MessageModel>> getMessagesOnce(
      String regionId, String? driverId) async {
    try {
      print('Test sorgusu başlatılıyor...');
      Query query = _firestore.collection('messages');
      if (regionId.isNotEmpty) {
        query = query.where('regionId', isEqualTo: regionId);
      }
      if (driverId != null && driverId.isNotEmpty) {
        query = query.where('driverId', isEqualTo: driverId);
      }
      final snapshot = await query.get();
      print('Test sorgusu tamamlandı: ${snapshot.docs.length} mesaj bulundu');
      return _parseMessages(snapshot);
    } catch (e) {
      print('Test sorgusu hatası: $e');
      return [];
    }
  }
  static Future<void> checkDriverFCMStatus(String regionId) async {
    try {
      print('🔍 Şoför FCM token durumu kontrol ediliyor...');
      print('- Bölge ID: $regionId');
      final driversSnap = await _firestore
          .collection('drivers')
          .where('regionId', isEqualTo: regionId)
          .get();
      if (driversSnap.docs.isEmpty) {
        print('⚠️ Bu bölgede hiç şoför bulunamadı!');
        return;
      }
      print('📋 Bölgedeki şoförler:');
      for (final doc in driversSnap.docs) {
        final data = doc.data();
        final name = data['name'] ?? 'İsimsiz';
        final hasFCM = data['fcmToken'] != null;
        final fcmToken = data['fcmToken'];
        print('- $name (${doc.id}): FCM ${hasFCM ? "✅" : "❌"}');
        if (hasFCM) {
          print('  Token: ${fcmToken.toString().substring(0, 20)}...');
        }
      }
      final usersSnap = await _firestore
          .collection('users')
          .where('regionId', isEqualTo: regionId)
          .get();
      if (usersSnap.docs.isNotEmpty) {
        print('\n👥 Users koleksiyonundaki kullanıcılar:');
        for (final doc in usersSnap.docs) {
          final data = doc.data();
          final name = data['name'] ?? 'İsimsiz';
          final role = data['role'] ?? 'Rol belirsiz';
          final hasFCM = data['fcmToken'] != null;
          final fcmToken = data['fcmToken'];
          if (role == 'Şoför') {
            print('- $name (${doc.id}): FCM ${hasFCM ? "✅" : "❌"}');
            if (hasFCM) {
              print('  Token: ${fcmToken.toString().substring(0, 20)}...');
            }
          }
        }
      } else {
        print('\n⚠️ Users koleksiyonunda kullanıcı bulunamadı');
      }
      print('\n💡 Öneriler:');
      print('1. Şoförlerin FCM token\'ı olup olmadığını kontrol edin');
      print('2. Şoförlerin role bilgisinin "Şoför" olduğundan emin olun');
      print('3. Şoförlerin regionId bilgisinin doğru olduğunu kontrol edin');
    } catch (e) {
      print('❌ Şoför FCM durumu kontrol hatası: $e');
    }
  }
  static Future<String?> deleteMessage(String messageId) async {
    try {
      print('🗑️ Mesaj silme işlemi başlatılıyor: $messageId');
      final messageDoc = await _firestore
          .collection('messages')
          .doc(messageId)
          .get();
      if (!messageDoc.exists) {
        print('❌ Mesaj bulunamadı: $messageId');
        return 'Mesaj bulunamadı';
      }
      final messageData = messageDoc.data();
      if (messageData == null) {
        print('❌ Mesaj verisi boş: $messageId');
        return 'Mesaj verisi boş';
      }
      await _firestore
          .collection('messages')
          .doc(messageId)
          .delete();
      print('✅ Mesaj başarıyla silindi: $messageId');
      return null;
    } catch (e) {
      print('❌ Mesaj silme hatası: $e');
      return 'Mesaj silinirken hata oluştu: $e';
    }
  }
}





