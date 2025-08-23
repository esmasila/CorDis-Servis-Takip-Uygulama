import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../service/chat_service.dart';
import '../models/message_model.dart';
class MessagesManagementScreen extends StatefulWidget {
  const MessagesManagementScreen({super.key});
  @override
  State<MessagesManagementScreen> createState() => _MessagesManagementScreenState();
}
class _MessagesManagementScreenState extends State<MessagesManagementScreen> {
  String? _selectedRegion;
  String? _selectedRegionId;
  List<Map<String, dynamic>> _regions = [];
  @override
  void initState() {
    super.initState();
    _loadRegions();
  }
  Future<void> _loadRegions() async {
    try {
      print('[MessagesManagement] Bölgeler yükleniyor...');
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('regions')
          .where('isActive', isEqualTo: true)
          .get();
      if (snapshot.docs.isEmpty) {
        print('[MessagesManagement] Aktif bölge bulunamadı, tüm bölgeler getiriliyor...');
        snapshot = await FirebaseFirestore.instance
            .collection('regions')
            .get();
      }
      print('[MessagesManagement] Bulunan bölge sayısı: ${snapshot.docs.length}');
      if (mounted) {
        setState(() {
          _regions = snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final regionName = data['name'] ?? doc.id;
            print('[MessagesManagement] Bölge: ${doc.id} - $regionName');
            return {
              'id': doc.id,
              'name': regionName,
            };
          }).toList();
          if (_regions.isNotEmpty) {
            _selectedRegion = _regions.first['name'];
            _selectedRegionId = _regions.first['id'];
            print('[MessagesManagement] Seçilen bölge: $_selectedRegion (ID: $_selectedRegionId)');
          } else {
            print('[MessagesManagement] Hiç bölge bulunamadı');
          }
        });
      }
    } catch (e) {
      print('[MessagesManagement] Bölge yükleme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bölgeler yüklenirken hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Mesaj Yönetimi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            try {
              print('[MessagesManagement] Back button pressed');
              Navigator.of(context).pop();
              print('[MessagesManagement] Navigation pop completed');
            } catch (e) {
              print('[MessagesManagement] Back navigation error: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Geri gitme hatası: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadRegions(),
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: Colors.green.shade700,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Bölge Seçin:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedRegion,
                        isExpanded: true,
                        hint: const Text('Bölge seçin'),
                        items: _regions.map((region) {
                          return DropdownMenuItem<String>(
                            value: region['name'] as String,
                            child: Text(
                              region['name'] as String,
                              style: const TextStyle(fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedRegion = value;
                            _selectedRegionId = _regions.firstWhere(
                              (region) => region['name'] == value,
                            )['id'];
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _selectedRegion == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_off,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Lütfen bir bölge seçin',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : StreamBuilder<List<MessageModel>>(
                    stream: ChatService.getMessagesForRegion(_selectedRegionId!),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 64,
                                color: Colors.red.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Mesajlar yüklenirken hata oluştu',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.red.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
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
                              Icon(
                                Icons.message_outlined,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Bu bölgede henüz mesaj bulunmuyor',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Mesajlar burada görünecek',
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
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  spreadRadius: 1,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: _getRoleColor(message.senderRole),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: _getRoleColor(message.senderRole).withOpacity(0.3),
                                      spreadRadius: 1,
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _getRoleIcon(message.senderRole),
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      message.senderName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getRoleColor(message.senderRole),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _getRoleText(message.senderRole),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.grey.shade200,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      message.content,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatTimestamp(message.timestamp),
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
                                icon: Icon(
                                  Icons.more_vert,
                                  color: Colors.grey.shade600,
                                ),
                                onSelected: (value) {
                                  if (value == 'delete') {
                                    _showDeleteConfirmation(message);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red, size: 20),
                                        SizedBox(width: 8),
                                        Text('Mesajı Sil'),
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
    );
  }
  void _showDeleteConfirmation(MessageModel message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mesajı Sil'),
        content: Text('${message.senderName} tarafından gönderilen mesajı silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(message.id);
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
  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.red.shade600;
      case 'driver':
      case 'şoför':
        return Colors.blue.shade600;
      case 'passenger':
      case 'yolcu':
        return Colors.green.shade600;
      default:
        return Colors.grey.shade600;
    }
  }
  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'driver':
      case 'şoför':
        return Icons.drive_eta;
      case 'passenger':
      case 'yolcu':
        return Icons.person;
      default:
        return Icons.person;
    }
  }
  String _getRoleText(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Admin';
      case 'driver':
      case 'şoför':
        return 'Şoför';
      case 'passenger':
      case 'yolcu':
        return 'Yolcu';
      default:
        return role;
    }
  }
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    if (difference.inDays > 0) {
      return '${difference.inDays} gün önce';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} saat önce';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} dakika önce';
    } else {
      return 'Az önce';
    }
  }
  Future<void> _deleteMessage(String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Mesaj başarıyla silindi'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Mesaj silinirken hata: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }
}
