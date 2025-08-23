import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../service/user_session.dart';
import '../service/chat_service.dart';
import '../models/message_model.dart';
import '../utils/app_colors.dart';
import '../service/notification_service.dart';
class ChatScreen extends StatefulWidget {
  final VoidCallback? onScreenOpen;
  const ChatScreen({super.key, this.onScreenOpen});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final user = FirebaseAuth.instance.currentUser!;
  String userName = '';
  bool _resolvingRegion = false;
  String? _regionResolveError;
  @override
  void initState() {
    super.initState();
    _loadUserName();
    NotificationService.instance.setChatScreenOpen(true);
    NotificationService.instance.startMessageNotifications();
    _ensureRegionInSession();
    _ensureDriverIdInSession();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onScreenOpen?.call();
    });
  }
  Future<void> _ensureRegionInSession() async {
    if (UserSession.regionId != null && UserSession.regionId!.isNotEmpty) {
      setState(() => _regionResolveError = null);
      return;
    }
    setState(() {
      _resolvingRegion = true;
      _regionResolveError = null;
    });
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = userDoc.data();
      String? regionId = data != null ? (data['regionId'] as String?) : null;
      if ((regionId == null || regionId.isEmpty)) {
        final String? driverId =
            (data != null ? data['driverId'] as String? : null) ??
                UserSession.driverId;
        if (driverId != null && driverId.isNotEmpty) {
          try {
            final driverDoc = await FirebaseFirestore.instance
                .collection('drivers')
                .doc(driverId)
                .get();
            if (driverDoc.exists) {
              regionId = (driverDoc.data()?['regionId'] as String?) ?? regionId;
            }
          } catch (_) {}
        }
      }
      if (regionId != null && regionId.isNotEmpty) {
        UserSession.regionId = regionId;
        await UserSession.saveToPreferences();
        setState(() => _regionResolveError = null);
      } else {
        setState(() => _regionResolveError = 'Bölge ataması bulunamadı.');
      }
    } catch (e) {
      setState(() => _regionResolveError = 'Bölge bilgisi alınamadı: $e');
    } finally {
      if (mounted) setState(() => _resolvingRegion = false);
    }
  }
  Future<void> _ensureDriverIdInSession() async {
    if (UserSession.driverId != null && UserSession.driverId!.isNotEmpty) {
      print('✅ DriverId zaten mevcut: ${UserSession.driverId}');
      return;
    }
    print('🔍 DriverId bulunamadı, otomatik olarak aranıyor...');
    try {
      final driverId = await _findAndSetDriverId();
      if (driverId != null) {
        print('✅ DriverId otomatik olarak bulundu ve set edildi: $driverId');
      } else {
        print('⚠️ DriverId bulunamadı');
      }
    } catch (e) {
      print('❌ DriverId bulma hatası: $e');
    }
  }
  Future<void> _loadUserName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted) {
        setState(() {
          userName = doc.data()?['name'] ?? 'Yolcu';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          userName = 'Yolcu';
        });
      }
    }
  }
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    print('🚀 Yolcu mesaj gönderme işlemi başlatılıyor:');
    print('- UserSession.regionId: ${UserSession.regionId}');
    print('- UserSession.driverId: ${UserSession.driverId}');
    print('- user.uid: ${user.uid}');
    print('- Mesaj içeriği: $text');
    String? effectiveDriverId = UserSession.driverId;
    if (effectiveDriverId == null || effectiveDriverId.isEmpty) {
      try {
        print(
            '🔍 ChatScreen: DriverId bulunamadı, otomatik olarak aranıyor...');
        effectiveDriverId = await _findAndSetDriverId();
        if (effectiveDriverId != null) {
          print(
              '✅ ChatScreen: DriverId otomatik olarak bulundu ve set edildi: $effectiveDriverId');
        } else {
          print(
              '⚠️ ChatScreen: DriverId bulunamadı, mesaj yine de gönderilecek');
        }
      } catch (e) {
        print('❌ ChatScreen: DriverId bulma hatası: $e');
      }
    } else {
      print('✅ ChatScreen: DriverId zaten mevcut: $effectiveDriverId');
    }
    try {
      final error = await ChatService.sendMessage(
        senderId: user.uid,
        senderName: userName,
        senderRole: 'Yolcu',
        content: text,
        regionId: UserSession.regionId ?? '',
        driverId: effectiveDriverId,
      );
      if (error != null) {
        print('❌ Mesaj gönderme hatası: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ $error'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        print(
            '✅ ChatScreen: Mesaj başarıyla gönderildi, Firebase Functions bildirim gönderecek');
        print('- DriverId: ${effectiveDriverId ?? "null"}');
        print('- RegionId: ${UserSession.regionId ?? "null"}');
        print('- SenderId: ${user.uid}');
        print('- SenderName: $userName');
        print('- SenderRole: Yolcu');
        print('🔍 Firebase Functions log\'larını kontrol edin...');
        _controller.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  const Text('✅ Mesaj gönderildi! Şoföre bildirim gidecek.'),
              duration: const Duration(seconds: 2),
              backgroundColor: AppColors.primary,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Yolcu mesaj gönderme exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  Future<void> _sendMissedAlert() async {
    String? effectiveDriverId = UserSession.driverId;
    if (effectiveDriverId == null || effectiveDriverId.isEmpty) {
      try {
        print(
            '🔍 ChatScreen: Missed Alert için DriverId bulunamadı, otomatik olarak aranıyor...');
        effectiveDriverId = await _findAndSetDriverId();
        if (effectiveDriverId != null) {
          print(
              '✅ ChatScreen: Missed Alert için DriverId bulundu: $effectiveDriverId');
        } else {
          print(
              '❌ ChatScreen: Missed Alert için DriverId bulunamadı, işlem iptal edildi');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text('❌ Şoför bilgisi bulunamadı, uyarı gönderilemedi'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      } catch (e) {
        print('❌ ChatScreen: Missed Alert için DriverId bulma hatası: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Hata: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }
    try {
      final error = await ChatService.sendMissedAlert(
        passengerId: user.uid,
        passengerName: userName,
        driverId: effectiveDriverId,
        regionId: UserSession.regionId ?? '',
      );
      if (mounted) {
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  const Text('🚨 Şoföre "Beni Kaçırdın" uyarısı gönderildi!'),
              backgroundColor: Colors.orange.shade600,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }
  Future<String?> _findAndSetDriverId() async {
    try {
      print('🔍 _findAndSetDriverId başlatılıyor...');
      final regionId = UserSession.regionId;
      if (regionId == null || regionId.isEmpty) {
        print('⚠️ RegionId bulunamadı, driverId bulunamaz');
        return null;
      }
      print('📍 Bölge ID: $regionId');
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          final existingDriverId = userData?['driverId'] as String?;
          if (existingDriverId != null && existingDriverId.isNotEmpty) {
            print(
                '✅ Users koleksiyonunda mevcut driverId bulundu: $existingDriverId');
            final driverDoc = await FirebaseFirestore.instance
                .collection('drivers')
                .doc(existingDriverId)
                .get();
            if (driverDoc.exists) {
              final driverData = driverDoc.data();
              if (driverData?['regionId'] == regionId &&
                  driverData?['isActive'] == true) {
                print(
                    '✅ Mevcut driverId hala geçerli, kullanılıyor: $existingDriverId');
                UserSession.driverId = existingDriverId;
                UserSession.driverName =
                    driverData?['name'] as String? ?? 'Bilinmeyen Şoför';
                UserSession.vehiclePlate =
                    driverData?['vehiclePlate'] as String? ?? 'Plaka Yok';
                await UserSession.saveToPreferences();
                return existingDriverId;
              } else {
                print('⚠️ Mevcut driverId artık geçerli değil, yeni aranacak');
              }
            }
          }
        }
      } catch (e) {
        print('⚠️ Users koleksiyonu kontrol hatası: $e');
      }
      print('🔍 Bölgedeki aktif şoför aranıyor...');
      final driverQuery = await FirebaseFirestore.instance
          .collection('drivers')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (driverQuery.docs.isNotEmpty) {
        final driverId = driverQuery.docs.first.id;
        final driverData = driverQuery.docs.first.data();
        print('✅ Aktif şoför bulundu: $driverId');
        print('- İsim: ${driverData['name'] ?? 'İsimsiz'}');
        print('- Plaka: ${driverData['vehiclePlate'] ?? 'Plaka Yok'}');
        print('- FCM Token: ${driverData['fcmToken'] != null ? '✅' : '❌'}');
        UserSession.driverId = driverId;
        UserSession.driverName =
            driverData['name'] as String? ?? 'Bilinmeyen Şoför';
        UserSession.vehiclePlate =
            driverData['vehiclePlate'] as String? ?? 'Plaka Yok';
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'driverId': driverId});
          print('✅ Users dokümanına driverId kaydedildi');
        } catch (e) {
          print('⚠️ Users dokümanına driverId kaydedilemedi: $e');
        }
        try {
          final userDriverDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(driverId)
              .get();
          if (!userDriverDoc.exists) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(driverId)
                .set({
              'name': driverData['name'] ?? 'Bilinmeyen Şoför',
              'role': 'Şoför',
              'regionId': regionId,
              'vehiclePlate': driverData['vehiclePlate'] ?? 'Plaka Yok',
              'isActive': true,
              'fcmToken': driverData['fcmToken'],
            }, SetOptions(merge: true));
            print('✅ Şoför users koleksiyonuna da eklendi: $driverId');
          } else {
            final userDriverData = userDriverDoc.data();
            if (userDriverData?['fcmToken'] == null &&
                driverData['fcmToken'] != null) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(driverId)
                  .update({
                'fcmToken': driverData['fcmToken'],
                'lastTokenUpdate': FieldValue.serverTimestamp(),
              });
              print(
                  '✅ Şoför FCM token\'ı users koleksiyonuna senkronize edildi');
            }
          }
        } catch (e) {
          print('⚠️ Şoför users koleksiyonuna eklenemedi: $e');
        }
        await UserSession.saveToPreferences();
        print('✅ UserSession kaydedildi');
        print('✅ DriverId başarıyla bulundu ve set edildi: $driverId');
        return driverId;
      } else {
        print('⚠️ Bölgede hiç şoför bulunamadı!');
        print('🔍 Bölgedeki tüm şoförler kontrol ediliyor...');
        final allDriversQuery = await FirebaseFirestore.instance
            .collection('drivers')
            .where('regionId', isEqualTo: regionId)
            .get();
        if (allDriversQuery.docs.isNotEmpty) {
          print('📋 Bölgedeki şoförler:');
          for (final doc in allDriversQuery.docs) {
            final data = doc.data();
            print(
                '  - ${doc.id}: ${data['name'] ?? 'İsimsiz'} (Aktif: ${data['isActive'] ?? 'null'})');
          }
        } else {
          print('❌ Bölgede hiç şoför bulunamadı!');
        }
        return null;
      }
    } catch (e) {
      print('❌ DriverId bulma hatası: $e');
      return null;
    }
  }
  Future<void> _sendQuickMessage(String message) async {
    print('Yolcu hızlı mesaj gönderme işlemi başlatılıyor:');
    print('- UserSession.regionId: ${UserSession.regionId}');
    print('- UserSession.driverId: ${UserSession.driverId}');
    String? effectiveDriverId = UserSession.driverId;
    if (effectiveDriverId == null || effectiveDriverId.isEmpty) {
      try {
        print(
            '🔍 ChatScreen: Hızlı mesaj için DriverId bulunamadı, otomatik olarak aranıyor...');
        effectiveDriverId = await _findAndSetDriverId();
        if (effectiveDriverId != null) {
          print(
              '✅ ChatScreen: Hızlı mesaj için DriverId bulundu: $effectiveDriverId');
        }
      } catch (e) {
        print('❌ ChatScreen: Hızlı mesaj için DriverId bulma hatası: $e');
      }
    }
    try {
      final error = await ChatService.sendMessage(
        senderId: user.uid,
        senderName: userName,
        senderRole: 'Yolcu',
        content: message,
        regionId: UserSession.regionId ?? '',
        driverId: effectiveDriverId,
      );
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Hızlı mesaj gönderildi!'),
            duration: const Duration(seconds: 1),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      print('Yolcu hızlı mesaj gönderme exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }
  Future<void> _checkDriverFCMStatus() async {
    if (UserSession.regionId == null || UserSession.regionId!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Bölge bilgisi bulunamadı'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    try {
      print('🔍 Şoför FCM durumu kontrol ediliyor...');
      print('- RegionId: ${UserSession.regionId}');
      print('- DriverId: ${UserSession.driverId ?? "null"}');
      final driversSnap = await FirebaseFirestore.instance
          .collection('drivers')
          .where('regionId', isEqualTo: UserSession.regionId)
          .get();
      print('📋 Bölgedeki şoförler:');
      for (final doc in driversSnap.docs) {
        final data = doc.data();
        print('  - ${doc.id}: ${data['name'] ?? 'İsimsiz'}');
        print('    FCM Token: ${data['fcmToken'] != null ? '✅' : '❌'}');
        print('    isActive: ${data['isActive'] ?? 'null'}');
      }
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('regionId', isEqualTo: UserSession.regionId)
          .where('role', isEqualTo: 'Şoför')
          .get();
      print('👥 Users koleksiyonundaki şoförler:');
      for (final doc in usersSnap.docs) {
        final data = doc.data();
        final hasFCM = data['fcmToken'] != null;
        print('  - ${doc.id}: ${data['name'] ?? 'İsimsiz'}');
        print('    FCM Token: ${hasFCM ? '✅' : '❌'}');
        if (hasFCM) {
          try {
            final driverDoc = await FirebaseFirestore.instance
                .collection('drivers')
                .doc(doc.id)
                .get();
            if (driverDoc.exists) {
              final driverData = driverDoc.data();
              if (driverData?['fcmToken'] == null) {
                await FirebaseFirestore.instance
                    .collection('drivers')
                    .doc(doc.id)
                    .update({
                  'fcmToken': data['fcmToken'],
                  'lastTokenUpdate': FieldValue.serverTimestamp(),
                });
                print('    ✅ FCM token drivers koleksiyonuna kopyalandı');
              } else {
                print('    ✅ Drivers koleksiyonunda zaten var');
              }
            }
          } catch (e) {
            print('    ⚠️ Senkronizasyon hatası: $e');
          }
        }
      }
      await ChatService.checkDriverFCMStatus(UserSession.regionId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('🔍 Şoför FCM durumu kontrol edildi, console\'a bakın'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ Kontrol hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Kontrol hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  Future<void> _debugSessionInfo() async {
    print('🐛 === DEBUG SESSION INFO ===');
    print('- UserSession.regionId: ${UserSession.regionId ?? "null"}');
    print('- UserSession.driverId: ${UserSession.driverId ?? "null"}');
    print('- UserSession.driverName: ${UserSession.driverName ?? "null"}');
    print('- UserSession.vehiclePlate: ${UserSession.vehiclePlate ?? "null"}');
    print('- user.uid: ${user.uid}');
    print('- userName: $userName');
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        print('📋 Users dokümanı:');
        print('  - regionId: ${userData?['regionId'] ?? "null"}');
        print('  - driverId: ${userData?['driverId'] ?? "null"}');
        print('  - role: ${userData?['role'] ?? "null"}');
        print('  - name: ${userData?['name'] ?? "null"}');
      } else {
        print('❌ Users dokümanı bulunamadı');
      }
      if (UserSession.regionId != null) {
        final regionDoc = await FirebaseFirestore.instance
            .collection('regions')
            .doc(UserSession.regionId)
            .get();
        if (regionDoc.exists) {
          final regionData = regionDoc.data();
          print('📍 Bölge bilgisi:');
          print('  - name: ${regionData?['name'] ?? "null"}');
          print('  - description: ${regionData?['description'] ?? "null"}');
        }
        final driversSnap = await FirebaseFirestore.instance
            .collection('drivers')
            .where('regionId', isEqualTo: UserSession.regionId)
            .get();
        print('🚌 Bölgedeki şoförler:');
        for (final doc in driversSnap.docs) {
          final data = doc.data();
          print('  - ${doc.id}: ${data['name'] ?? 'İsimsiz'}');
          print('    isActive: ${data['isActive'] ?? 'null'}');
          print('    FCM Token: ${data['fcmToken'] != null ? '✅' : '❌'}');
        }
      }
    } catch (e) {
      print('❌ Debug hatası: $e');
    }
    print('🐛 === DEBUG END ===');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🐛 Debug bilgileri console\'a yazıldı'),
          backgroundColor: Colors.purple,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ElevatedButton.icon(
                    onPressed: _sendMissedAlert,
                    icon: const Icon(Icons.warning, color: Colors.white),
                    label: const Text(
                      "🚨 BENİ KAÇIRDIN!",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.flash_on, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Hızlı Mesajlar',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QuickMessageButton(
                      text: "👋 Merhaba",
                      onPressed: () =>
                          _sendQuickMessage("👋 Merhaba şoför bey!"),
                    ),
                    _QuickMessageButton(
                      text: "📍 Neredesin?",
                      onPressed: () =>
                          _sendQuickMessage("📍 Şu anda neredesiniz?"),
                    ),
                    _QuickMessageButton(
                      text: "⏰ Ne zaman?",
                      onPressed: () => _sendQuickMessage(
                          "⏰ Durağıma ne zaman geleceksiniz?"),
                    ),
                    _QuickMessageButton(
                      text: "🏃 Koşuyorum",
                      onPressed: () => _sendQuickMessage(
                          "🏃 Durağa koşuyorum, bekleyin lütfen!"),
                    ),
                    _QuickMessageButton(
                      text: "🙏 Teşekkürler",
                      onPressed: () => _sendQuickMessage("🙏 Teşekkür ederim!"),
                    ),
                    _QuickMessageButton(
                      text: "🔍 Kontrol",
                      onPressed: _checkDriverFCMStatus,
                    ),
                    _QuickMessageButton(
                      text: "🐛 Debug",
                      onPressed: _debugSessionInfo,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: (UserSession.regionId == null ||
                    UserSession.regionId!.isEmpty)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_resolvingRegion) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          const Text('Bölge bilgisi çözümleniyor...'),
                        ] else ...[
                          Icon(Icons.info_outline,
                              size: 64, color: Colors.orange.shade300),
                          const SizedBox(height: 12),
                          Text(
                            _regionResolveError ?? 'Bölge bilgisi bulunamadı',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Bölgeyi otomatik çözmeyi deneyin.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _ensureRegionInSession,
                            icon: const Icon(Icons.public),
                            label: const Text('Bölgeyi Çöz'),
                          ),
                        ],
                      ],
                    ),
                  )
                : StreamBuilder<List<MessageModel>>(
                    stream: ChatService.getRegionMessages(
                      UserSession.regionId!,
                      UserSession
                          .driverId,
                    ),
                    builder: (ctx, snapshot) {
                      print('Yolcu StreamBuilder durumu:');
                      print('- connectionState: ${snapshot.connectionState}');
                      print('- hasError: ${snapshot.hasError}');
                      print('- hasData: ${snapshot.hasData}');
                      print('- regionId: ${UserSession.regionId}');
                      if (snapshot.hasData) {
                        print('- data length: ${snapshot.data!.length}');
                        for (var msg in snapshot.data!) {
                          print(
                              '  - Mesaj: ${msg.senderName} (${msg.senderRole}): ${msg.content}');
                        }
                      }
                      if (snapshot.hasError) {
                        print('- error: ${snapshot.error}');
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Mesajlar yükleniyor...'),
                            ],
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error,
                                  size: 64, color: Colors.red.shade300),
                              const SizedBox(height: 16),
                              Text(
                                'Mesajlar yüklenirken hata oluştu',
                                style: TextStyle(color: Colors.red.shade600),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Hata: ${snapshot.error}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => setState(() {}),
                                child: const Text('Tekrar Dene'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline,
                                  size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                'Henüz mesaj yok',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Grup sohbetine katılın!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final messages = snapshot.data!;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollController.hasClients &&
                            messages.isNotEmpty) {
                          _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      });
                      return ListView.builder(
                        controller: _scrollController,
                        reverse:
                            false,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (ctx, i) {
                          final message = messages[i];
                          final isMe = message.senderId == user.uid;
                          if (!isMe && !message.isRead) {
                            ChatService.markMessageAsRead(message.id);
                          }
                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () => _showDeleteDialog(message),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.75,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? AppColors.primary
                                      : message.content.contains('🚨')
                                          ? Colors.red.shade100
                                          : Colors.white,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: isMe
                                        ? const Radius.circular(16)
                                        : const Radius.circular(4),
                                    bottomRight: isMe
                                        ? const Radius.circular(4)
                                        : const Radius.circular(16),
                                  ),
                                  border: message.content.contains('🚨')
                                      ? Border.all(color: Colors.red, width: 2)
                                      : null,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.shade200,
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          message.senderName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: isMe
                                                ? Colors.white70
                                                : message.senderRole == 'Şoför'
                                                    ? AppColors.primaryDark
                                                    : AppColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          message.senderRole == 'Şoför'
                                              ? Icons.drive_eta
                                              : Icons.person,
                                          size: 12,
                                          color: isMe
                                              ? Colors.white70
                                              : message.senderRole == 'Şoför'
                                                  ? AppColors.primaryDark
                                                  : AppColors.textSecondary,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      message.content,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: isMe
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight:
                                            message.content.contains('🚨')
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatTime(message.timestamp),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isMe
                                            ? Colors.white60
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Grup sohbetine mesaj yazın...',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send),
                    color: Colors.white,
                    iconSize: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inDays > 0) {
      return '${dateTime.day}/${dateTime.month} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}s önce';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}dk önce';
    } else {
      return 'Şimdi';
    }
  }
  Future<void> _showDeleteDialog(MessageModel message) async {
    final isMe = message.senderId == user.uid;
    if (!isMe) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Sadece kendi mesajlarınızı silebilirsiniz'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.delete_forever, color: Colors.red.shade600, size: 24),
              const SizedBox(width: 8),
              const Text('Mesajı Sil'),
            ],
          ),
          content: Text(
            'Bu mesajı silmek istediğinizden emin misiniz?\n\n"${message.content}"',
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'İptal',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
    if (result == true) {
      await _deleteMessage(message);
    }
  }
  Future<void> _deleteMessage(MessageModel message) async {
    try {
      setState(() {
      });
      final error = await ChatService.deleteMessage(message.id);
      if (error != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Mesaj silinemedi: $error'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Mesaj başarıyla silindi'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    NotificationService.instance.setChatScreenOpen(false);
    super.dispose();
  }
}
class _QuickMessageButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  const _QuickMessageButton({
    required this.text,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary.withOpacity(0.06),
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.primary.withOpacity(0.2)),
        ),
        elevation: 0,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
    );
  }
}
