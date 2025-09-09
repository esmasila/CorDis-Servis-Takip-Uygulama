import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widget/snackbar.dart';
import 'firestore_service.dart';
class NotificationManagementScreen extends StatefulWidget {
  const NotificationManagementScreen({super.key});
  @override
  State<NotificationManagementScreen> createState() =>
      _NotificationManagementScreenState();
}
class _NotificationManagementScreenState
    extends State<NotificationManagementScreen> {
  String? _selectedTargetRole;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Bildirim Yönetimi'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            try {
              print('[NotificationManagement] Back button pressed');
              Navigator.of(context).pop();
              print('[NotificationManagement] Navigation pop completed');
            } catch (e) {
              print('[NotificationManagement] Back navigation error: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Geri gitme hatası: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Hedef Kitle Filtresi',
                border: OutlineInputBorder(),
              ),
              value: _selectedTargetRole,
              items: const [
                DropdownMenuItem(
                  value: null,
                  child: Text('Tüm Bildirimler'),
                ),
                DropdownMenuItem(
                  value: 'Şoför',
                  child: Text('Şoförlere Gönderilen'),
                ),
                DropdownMenuItem(
                  value: 'Yolcu',
                  child: Text('Yolculara Gönderilen'),
                ),
                DropdownMenuItem(
                  value: 'general',
                  child: Text('Genel Bildirimler'),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedTargetRole = val;
                });
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _buildNotificationsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Hata: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final notifications = snapshot.data!.docs;
                if (notifications.isEmpty) {
                  return const Center(
                    child: Text(
                      'Henüz bildirim bulunmuyor.\nYeni bildirim göndermek için + butonuna tıklayın.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final notification =
                        notifications[index].data() as Map<String, dynamic>;
                    final notificationId = notifications[index].id;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          Icons.notifications,
                          color: notification['isRead'] == true
                              ? Colors.grey
                              : Colors.blue,
                          size: 32,
                        ),
                        title: Text(
                          notification['title'] ?? 'Başlıksız Bildirim',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notification['message'] ?? 'Mesaj yok',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.group,
                                    size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  _getTargetText(notification),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Icon(Icons.access_time,
                                    size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  _formatTime(notification['createdAt']),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'view':
                                _viewNotification(notification);
                                break;
                              case 'delete':
                                _deleteNotification(notificationId);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'view',
                              child: Row(
                                children: [
                                  Icon(Icons.visibility, size: 16),
                                  SizedBox(width: 8),
                                  Text('Görüntüle'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete,
                                      size: 16, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Sil',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSendNotificationDialog(),
        backgroundColor: Colors.blue.shade700,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
  Stream<QuerySnapshot> _buildNotificationsStream() {
    Query query = FirebaseFirestore.instance.collection('notifications');
    if (_selectedTargetRole != null) {
      if (_selectedTargetRole == 'general') {
        query = query.where('targetRole', isNull: true);
      } else {
        query = query.where('targetRole', isEqualTo: _selectedTargetRole);
      }
    }
    return query.orderBy('createdAt', descending: true).snapshots();
  }
  String _getTargetText(Map<String, dynamic> notification) {
    final targetRole = notification['targetRole'];
    final userId = notification['userId'];
    if (userId != null) {
      return 'Bireysel';
    } else if (targetRole == null) {
      return 'Herkese';
    } else {
      return targetRole;
    }
  }
  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'Bilinmeyen';
    try {
      final DateTime dateTime = (timestamp as Timestamp).toDate();
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      if (difference.inDays > 0) {
        return '${difference.inDays} gün önce';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} saat önce';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} dakika önce';
      } else {
        return 'Az önce';
      }
    } catch (e) {
      return 'Geçersiz zaman';
    }
  }
  void _showSendNotificationDialog() {
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    String? selectedTargetRole;
    String? selectedUserId;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Bildirim Gönder'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Bildirim Başlığı *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: messageController,
                    decoration: const InputDecoration(
                      labelText: 'Bildirim Mesajı *',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Hedef Kitle *',
                      border: OutlineInputBorder(),
                    ),
                    value: selectedTargetRole,
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('Herkese Gönder'),
                      ),
                      DropdownMenuItem(
                        value: 'Şoför',
                        child: Text('Sadece Şoförlere'),
                      ),
                      DropdownMenuItem(
                        value: 'Yolcu',
                        child: Text('Sadece Yolculara'),
                      ),
                      DropdownMenuItem(
                        value: 'individual',
                        child: Text('Belirli Kullanıcıya'),
                      ),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        selectedTargetRole = val;
                        selectedUserId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (selectedTargetRole == 'individual')
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .orderBy('name')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const CircularProgressIndicator();
                        }
                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Kullanıcı Seç *',
                            border: OutlineInputBorder(),
                          ),
                          value: selectedUserId,
                          items: snapshot.data!.docs.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return DropdownMenuItem(
                              value: doc.id,
                              child: Text('${data['name']} (${data['role']})'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedUserId = val;
                            });
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.trim().isEmpty ||
                    messageController.text.trim().isEmpty) {
                  showSnackBar(
                    text: 'Lütfen başlık ve mesaj alanlarını doldurun.',
                    backgroundColor: Colors.red.shade700,
                  );
                  return;
                }
                if (selectedTargetRole == 'individual' &&
                    selectedUserId == null) {
                  showSnackBar(
                    text: 'Lütfen bir kullanıcı seçin.',
                    backgroundColor: Colors.red.shade700,
                  );
                  return;
                }
                try {
                  if (selectedTargetRole == 'individual') {
                    await AdminFirestoreService.sendNotificationToUser(
                      userId: selectedUserId!,
                      title: titleController.text.trim(),
                      message: messageController.text.trim(),
                    );
                  } else {
                    await AdminFirestoreService.sendNotificationToAll(
                      title: titleController.text.trim(),
                      message: messageController.text.trim(),
                      targetRole: selectedTargetRole,
                    );
                  }
                  showSnackBar(text: 'Bildirim başarıyla gönderildi!');
                  Navigator.pop(context);
                } catch (e) {
                  showSnackBar(
                    text: 'Bildirim gönderilirken hata oluştu: $e',
                    backgroundColor: Colors.red.shade700,
                  );
                }
              },
              child: const Text('Gönder'),
            ),
          ],
        ),
      ),
    );
  }
  void _viewNotification(Map<String, dynamic> notification) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(notification['title'] ?? 'Başlıksız Bildirim'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Mesaj:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(notification['message'] ?? 'Mesaj yok'),
              const SizedBox(height: 16),
              const Text(
                'Detaylar:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Hedef: ${_getTargetText(notification)}'),
              Text(
                  'Gönderim Zamanı: ${_formatTime(notification['createdAt'])}'),
              Text(
                  'Durum: ${notification['isRead'] == true ? 'Okundu' : 'Okunmadı'}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
  void _deleteNotification(String notificationId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bildirim Sil'),
        content: const Text('Bu bildirimi silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await AdminFirestoreService.deleteNotification(notificationId);
                showSnackBar(text: 'Bildirim başarıyla silindi!');
                Navigator.pop(context);
              } catch (e) {
                showSnackBar(
                  text: 'Bildirim silinirken hata oluştu: $e',
                  backgroundColor: Colors.red.shade700,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
}

// Updated


// Updated Again

