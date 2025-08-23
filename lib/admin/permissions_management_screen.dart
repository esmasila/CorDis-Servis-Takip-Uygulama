import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../service/permission_service.dart';
import '../models/permission_model.dart';
class PermissionsManagementScreen extends StatefulWidget {
  const PermissionsManagementScreen({super.key});
  @override
  State<PermissionsManagementScreen> createState() =>
      _PermissionsManagementScreenState();
}
class _PermissionsManagementScreenState
    extends State<PermissionsManagementScreen> {
  String? _selectedDriver;
  List<Map<String, dynamic>> _drivers = [];
  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }
  Future<void> _loadDrivers() async {
    try {
      print('[PermissionsManagement] Şoförler yükleniyor...');
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('isActive', isEqualTo: true)
          .get();
      if (snapshot.docs.isEmpty) {
        print(
            '[PermissionsManagement] Aktif şoför bulunamadı, tüm şoförler getiriliyor...');
        snapshot = await FirebaseFirestore.instance.collection('drivers').get();
      }
      print(
          '[PermissionsManagement] Bulunan şoför sayısı: ${snapshot.docs.length}');
      if (mounted) {
        setState(() {
          _drivers = snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            print('[PermissionsManagement] Şoför: ${doc.id} - ${data['name']}');
            return {
              'id': doc.id,
              'name': data['name'] ?? 'İsim Yok',
              'vehiclePlate': data['vehiclePlate'] ?? 'Plaka Yok',
              'regionId': data['regionId'] ?? 'Bölge Yok',
            };
          }).toList();
          if (_drivers.isNotEmpty) {
            _selectedDriver = _drivers.first['id'];
            print('[PermissionsManagement] Seçilen şoför: $_selectedDriver');
          } else {
            print('[PermissionsManagement] Hiç şoför bulunamadı');
          }
        });
      }
    } catch (e) {
      print('[PermissionsManagement] Şoför yükleme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Şoförler yüklenirken hata: $e'),
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
          'İzin Yönetimi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            try {
              print('[PermissionsManagement] Back button pressed');
              Navigator.of(context).pop();
              print('[PermissionsManagement] Navigation pop completed');
            } catch (e) {
              print('[PermissionsManagement] Back navigation error: $e');
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
            onPressed: () => _loadDrivers(),
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
                  Icons.drive_eta,
                  color: Colors.orange.shade700,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Şoför Seçin:',
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
                        value: _selectedDriver,
                        isExpanded: true,
                        hint: const Text('Şoför seçin'),
                        items: _drivers.map((driver) {
                          return DropdownMenuItem<String>(
                            value: driver['id'],
                            child: Text(
                              '${driver['name']} (${driver['vehiclePlate']}) - ${driver['regionId']}',
                              style: const TextStyle(fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedDriver = value;
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
            child: _selectedDriver == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_off,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Lütfen bir şoför seçin',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : StreamBuilder<List<PermissionModel>>(
                    stream: PermissionService.getDriverPermissions(
                        _selectedDriver!),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.orange),
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
                                'İzinler yüklenirken hata oluştu',
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
                                Icons.event_available,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Bu şoför için henüz izin bulunmuyor',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'İzinler burada görünecek',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final permissions = snapshot.data!;
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: permissions.length,
                        itemBuilder: (context, index) {
                          final permission = permissions[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: permission.isActive
                                    ? Colors.green.shade200
                                    : Colors.red.shade200,
                                width: 1,
                              ),
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
                                  color: _getPermissionColor(permission.type),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          _getPermissionColor(permission.type)
                                              .withOpacity(0.3),
                                      spreadRadius: 1,
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _getPermissionIcon(permission.type),
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      permission.userName,
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
                                      color: permission.isActive
                                          ? Colors.green
                                          : Colors.red,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      permission.isActive
                                          ? 'Aktif'
                                          : 'İptal Edildi',
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
                                      color:
                                          _getPermissionColor(permission.type)
                                              .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color:
                                            _getPermissionColor(permission.type)
                                                .withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _getPermissionTypeText(
                                              permission.type),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: _getPermissionColor(
                                                permission.type),
                                          ),
                                        ),
                                        if (permission.reason != null &&
                                            permission.reason!.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Sebep: ${permission.reason}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        size: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatPermissionDate(permission),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: permission.isActive
                                  ? PopupMenuButton<String>(
                                      icon: Icon(
                                        Icons.more_vert,
                                        color: Colors.grey.shade600,
                                      ),
                                      onSelected: (value) {
                                        if (value == 'cancel') {
                                          _showCancelConfirmation(permission);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'cancel',
                                          child: Row(
                                            children: [
                                              Icon(Icons.cancel,
                                                  color: Colors.red, size: 20),
                                              SizedBox(width: 8),
                                              Text('İzni İptal Et'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : Icon(
                                      Icons.block,
                                      color: Colors.grey.shade400,
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
  void _showCancelConfirmation(PermissionModel permission) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İzni İptal Et'),
        content: Text(
            '${permission.userName} kullanıcısının iznini iptal etmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hayır'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelPermission(permission.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );
  }
  Color _getPermissionColor(PermissionType type) {
    switch (type) {
      case PermissionType.morningToday:
      case PermissionType.morningTomorrow:
        return Colors.orange.shade600;
      case PermissionType.eveningToday:
        return const Color(0xFF6366F1);
      case PermissionType.allToday:
      case PermissionType.allTomorrow:
        return Colors.red.shade600;
      case PermissionType.vacation:
        return Colors.blue.shade600;
      default:
        return Colors.grey.shade600;
    }
  }
  IconData _getPermissionIcon(PermissionType type) {
    switch (type) {
      case PermissionType.morningToday:
      case PermissionType.morningTomorrow:
        return Icons.wb_sunny;
      case PermissionType.eveningToday:
        return Icons.nights_stay;
      case PermissionType.allToday:
      case PermissionType.allTomorrow:
        return Icons.cancel;
      case PermissionType.vacation:
        return Icons.beach_access;
      default:
        return Icons.event_busy;
    }
  }
  String _getPermissionTypeText(PermissionType type) {
    switch (type) {
      case PermissionType.morningToday:
        return 'Bugün Sabah Servisi Yok';
      case PermissionType.eveningToday:
        return 'Bugün Akşam Servisi Yok';
      case PermissionType.morningTomorrow:
        return 'Yarın Sabah Servisi Yok';
      case PermissionType.allToday:
        return 'Bugün Hiç Servis Yok';
      case PermissionType.allTomorrow:
        return 'Yarın Hiç Servis Yok';
      case PermissionType.vacation:
        return 'Tatil İzni';
      default:
        return 'Bilinmeyen İzin Türü';
    }
  }
  String _formatPermissionDate(PermissionModel permission) {
    final startDate = permission.startDate;
    final endDate = permission.endDate;
    if (endDate != null) {
      return '${_formatDate(startDate)} - ${_formatDate(endDate)}';
    } else {
      return _formatDate(startDate);
    }
  }
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(date.year, date.month, date.day);
    if (targetDate == today) {
      return 'Bugün';
    } else if (targetDate == today.add(const Duration(days: 1))) {
      return 'Yarın';
    } else if (targetDate == today.subtract(const Duration(days: 1))) {
      return 'Dün';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
  Future<void> _cancelPermission(String permissionId) async {
    try {
      final error = await PermissionService.cancelPermission(permissionId);
      if (mounted) {
        if (error == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('İzin başarıyla iptal edildi'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text(error)),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('İzin iptal edilirken hata: $e')),
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
