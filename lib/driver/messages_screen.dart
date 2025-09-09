import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../service/user_session.dart';
import '../service/chat_service.dart';
import '../models/message_model.dart';
import '../utils/app_colors.dart';
import '../service/notification_service.dart';
import '../service/cache_service.dart';
class MessagesScreen extends StatefulWidget {
  final String? driverId;
  final VoidCallback? onScreenOpen;
  const MessagesScreen({super.key, this.driverId, this.onScreenOpen});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}
class _MessagesScreenState extends State<MessagesScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final user = FirebaseAuth.instance.currentUser!;
  String? userName;
  @override
  void initState() {
    super.initState();
    _loadUserName();
    NotificationService.instance.setChatScreenOpen(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onScreenOpen?.call();
    });
  }
  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    NotificationService.instance.setChatScreenOpen(false);
    super.dispose();
  }
  Future<void> _loadUserName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted) {
        setState(() {
          userName = doc.data()?['name'] ?? 'Şoför';
        });
      }
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final regionId = data['regionId'] as String?;
        if (regionId != null && regionId.isNotEmpty) {
          UserSession.regionId = regionId;
          print('✅ Şoför bölge bilgisi güncellendi: $regionId');
        } else {
          try {
            final driverDoc = await FirebaseFirestore.instance
                .collection('drivers')
                .doc(user.uid)
                .get();
            if (driverDoc.exists) {
              final driverData = driverDoc.data() as Map<String, dynamic>;
              final driverRegionId = driverData['regionId'] as String?;
              if (driverRegionId != null && driverRegionId.isNotEmpty) {
                UserSession.regionId = driverRegionId;
                print(
                    '✅ Şoför bölge bilgisi drivers koleksiyonundan güncellendi: $driverRegionId');
              }
            }
          } catch (e) {
            print('⚠️ Drivers koleksiyonundan bölge bilgisi alınamadı: $e');
          }
        }
        UserSession.driverId = user.uid;
        UserSession.driverName = data['name'] ?? 'Şoför';
        UserSession.vehiclePlate = data['vehiclePlate'] ?? '38ILM3729';
        print('✅ Şoför UserSession güncellendi:');
        print('  - driverId: ${UserSession.driverId}');
        print('  - driverName: ${UserSession.driverName}');
        print('  - vehiclePlate: ${UserSession.vehiclePlate}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          userName = 'Şoför';
        });
      }
    }
  }
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || userName == null) return;
    print('🚀 Şoför mesaj gönderme işlemi başlatılıyor:');
    print('- UserSession.regionId: ${UserSession.regionId}');
    print('- user.uid: ${user.uid}');
    print('- Mesaj içeriği: $text');
    if (UserSession.regionId == null || UserSession.regionId!.isEmpty) {
      print('❌ Bölge bilgisi bulunamadı, yeniden yükleniyor...');
      await _loadUserName();
      if (UserSession.regionId == null || UserSession.regionId!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  '❌ Bölge bilgisi bulunamadı, lütfen uygulamayı yeniden başlatın.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    }
    try {
      final error = await ChatService.sendMessage(
        senderId: user.uid,
        senderName: userName!,
        senderRole: 'Şoför',
        content: text,
        regionId: UserSession.regionId ?? '',
        driverId: user.uid,
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
            '✅ Mesaj başarıyla gönderildi, Firebase Functions bildirim gönderecek');
        _controller.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Mesaj gönderildi! Yolculara bildirim gidecek.'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Şoför mesaj gönderme exception: $e');
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
  Future<void> _sendQuickMessage(String message) async {
    if (userName == null) return;
    print('🚀 Şoför hızlı mesaj gönderme işlemi başlatılıyor:');
    print('- Mesaj: $message');
    print('- UserSession.regionId: ${UserSession.regionId}');
    if (UserSession.regionId == null || UserSession.regionId!.isEmpty) {
      print('❌ Bölge bilgisi bulunamadı, yeniden yükleniyor...');
      await _loadUserName();
      if (UserSession.regionId == null || UserSession.regionId!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  '❌ Bölge bilgisi bulunamadı, lütfen uygulamayı yeniden başlatın.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    }
    try {
      final error = await ChatService.sendMessage(
        senderId: user.uid,
        senderName: userName!,
        senderRole: 'Şoför',
        content: message,
        regionId: UserSession.regionId ?? '',
        driverId: user.uid,
      );
      if (error != null) {
        print('❌ Hızlı mesaj gönderme hatası: $error');
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
            '✅ Hızlı mesaj başarıyla gönderildi, Firebase Functions bildirim gönderecek');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('✅ Hızlı mesaj gönderildi! Yolculara bildirim gidecek.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Şoför hızlı mesaj gönderme exception: $e');
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
  Future<void> _debugSessionInfo() async {
    print('🐛 === DRIVER DEBUG SESSION INFO ===');
    print('- UserSession.regionId: ${UserSession.regionId ?? "null"}');
    print('- UserSession.driverId: ${UserSession.driverId ?? "null"}');
    print('- UserSession.driverName: ${UserSession.driverName ?? "null"}');
    print('- UserSession.vehiclePlate: ${UserSession.vehiclePlate ?? "null"}');
    print('- user.uid: ${user.uid}');
    print('- userName: $userName');
    print('- widget.driverId: ${widget.driverId}');
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
        print('  - fcmToken: ${userData?['fcmToken'] != null ? '✅' : '❌'}');
      } else {
        print('❌ Users dokümanı bulunamadı');
      }
      final driverDoc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .get();
      if (driverDoc.exists) {
        final driverData = driverDoc.data();
        print('🚌 Drivers dokümanı:');
        print('  - regionId: ${driverData?['regionId'] ?? "null"}');
        print('  - name: ${driverData?['name'] ?? "null"}');
        print('  - isActive: ${driverData?['isActive'] ?? "null"}');
        print('  - fcmToken: ${driverData?['fcmToken'] != null ? '✅' : '❌'}');
        if (driverData?['fcmToken'] != null) {
          print(
              '    Token: ${driverData?['fcmToken'].toString().substring(0, 20)}...');
        }
      } else {
        print('❌ Drivers dokümanı bulunamadı');
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
        final passengersSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('regionId', isEqualTo: UserSession.regionId)
            .where('role', isEqualTo: 'Yolcu')
            .get();
        print('👥 Bölgedeki yolcular:');
        for (final doc in passengersSnap.docs) {
          final data = doc.data();
          print('  - ${doc.id}: ${data['name'] ?? 'İsimsiz'}');
          print('    FCM Token: ${data['fcmToken'] != null ? '✅' : '❌'}');
        }
      }
    } catch (e) {
      print('❌ Debug hatası: $e');
    }
    print('🐛 === DRIVER DEBUG END ===');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🐛 Şoför debug bilgileri console\'a yazıldı'),
          backgroundColor: Colors.purple,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        toolbarHeight: canPop ? 56 : 0,
        elevation: 0,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        flexibleSpace: canPop
            ? SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new,
                            size: 18,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Mesajlar',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.warningAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.flash_on_rounded,
                        color: AppColors.warningAccent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Hızlı Mesajlar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth;
                  final crossAxisCount = maxWidth >= 640
                      ? 4
                      : maxWidth >= 480
                          ? 3
                          : 2;
                  final items = <Widget>[
                    _buildQuickMessageChip(
                        "🚌 Yola çıktım", "🚌 Yola çıktım, hazır olun!"),
                    _buildQuickMessageChip("⏰ 5 dk geç",
                        "⏰ 5 dakika gecikeceğim, bekleyin lütfen."),
                    _buildQuickMessageChip("🚦 Trafik var",
                        "🚦 Trafik yoğunluğu nedeniyle gecikiyorum."),
                    _buildQuickMessageChip(
                        "✅ Geliyorum", "✅ Durağınıza geliyorum, hazır olun."),
                    _buildQuickMessageChip("🔧 Arıza var",
                        "🔧 Araçta teknik sorun var, alternatif çözüm aranıyor."),
                    _buildQuickMessageChip("☔ Hava kötü",
                        "☔ Hava koşulları nedeniyle yavaş ilerliyorum."),
                    _buildDebugButton(),
                  ];
                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 3.2,
                    ),
                    itemCount: items.length,
                    itemBuilder: (ctx, i) => items[i],
                  );
                }),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: StreamBuilder<List<MessageModel>>(
                stream: ChatService.getRegionMessages(
                  UserSession.regionId ?? '',
                  null,
                ),
                builder: (ctx, snapshot) {
                  if (snapshot.hasData) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppColors.primary),
                          const SizedBox(height: 16),
                          Text(
                            'Mesajlar yükleniyor...',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: 48, color: AppColors.error),
                          const SizedBox(height: 16),
                          Text(
                            'Mesajlar yüklenemedi',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tekrar deneyin',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
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
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz mesaj yok',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Servis grubunuzla iletişime geçin!',
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
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: messages.length,
                    itemBuilder: (ctx, i) {
                      final message = messages[i];
                      final isMe = message.senderId == user.uid;
                      if (!isMe && !message.isRead) {
                        ChatService.markMessageAsRead(message.id);
                      }
                      return _buildModernMessageBubble(message, isMe);
                    },
                  );
                },
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Mesajınızı yazın...',
                          border: InputBorder.none,
                          isCollapsed: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                        ),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                        maxLines: 3,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildQuickMessageChip(String text, String message) {
    return GestureDetector(
      onTap: () => _sendQuickMessage(message),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
  Widget _buildDebugButton() {
    return GestureDetector(
      onTap: _debugSessionInfo,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.purple.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.purple.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: const Text(
          '🐛 Debug',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.purple,
          ),
        ),
      ),
    );
  }
  Widget _buildModernMessageBubble(MessageModel message, bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showDeleteDialog(message),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isMe ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomRight:
                  isMe ? const Radius.circular(4) : const Radius.circular(16),
              bottomLeft:
                  !isMe ? const Radius.circular(4) : const Radius.circular(16),
            ),
            border: !isMe
                ? Border.all(color: Colors.grey.shade200, width: 1)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe) ...[
                Text(
                  '${message.senderName} • ${message.senderRole}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                message.content,
                style: TextStyle(
                  fontSize: 14,
                  color: isMe ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: isMe
                      ? Colors.white.withOpacity(0.7)
                      : AppColors.textLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);
    if (messageDate == today) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
}

// Updated

