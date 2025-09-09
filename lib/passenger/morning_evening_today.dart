import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../service/permission_service.dart';
import '../service/user_session.dart';
import '../models/permission_model.dart';
class MorningEveningToday extends StatefulWidget {
  const MorningEveningToday({super.key});
  @override
  State<MorningEveningToday> createState() => _MorningEveningTodayState();
}
class _MorningEveningTodayState extends State<MorningEveningToday> {
  final user = FirebaseAuth.instance.currentUser!;
  String? userName;
  DateTime? vacationStartDate;
  DateTime? vacationEndDate;
  final TextEditingController _reasonController = TextEditingController();
  @override
  void initState() {
    super.initState();
    _loadUserName();
  }
  Future<void> _loadUserName() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    setState(() {
      userName = doc.data()?['name'] ?? 'Yolcu';
    });
  }
  Future<void> _createPermission(PermissionType type) async {
    if (userName == null) return;
    DateTime startDate;
    DateTime? endDate;
    switch (type) {
      case PermissionType.morningToday:
      case PermissionType.eveningToday:
      case PermissionType.allToday:
        startDate = DateTime.now();
        break;
      case PermissionType.morningTomorrow:
      case PermissionType.allTomorrow:
        startDate = DateTime.now().add(const Duration(days: 1));
        break;
      case PermissionType.vacation:
        if (vacationStartDate == null || vacationEndDate == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lütfen tatil tarihlerini seçin')),
          );
          return;
        }
        startDate = vacationStartDate!;
        endDate = vacationEndDate!;
        break;
    }
    final error = await PermissionService.createPermission(
      userId: user.uid,
      userName: userName!,
      type: type,
      startDate: startDate,
      endDate: endDate,
      reason: _reasonController.text.trim().isEmpty
          ? null
          : _reasonController.text.trim(),
      driverId: UserSession.driverId,
    );
    if (mounted) {
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İzin başarıyla oluşturuldu'),
            backgroundColor: Colors.green,
          ),
        );
        _reasonController.clear();
        setState(() {
          vacationStartDate = null;
          vacationEndDate = null;
        });
      }
    }
  }
  Future<void> _selectVacationDates() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: vacationStartDate != null && vacationEndDate != null
          ? DateTimeRange(start: vacationStartDate!, end: vacationEndDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        vacationStartDate = picked.start;
        vacationEndDate = picked.end;
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 4,
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bugün İçin İzinler',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PermissionButton(
                        text: 'Bugün sabah yokum',
                        icon: Icons.wb_sunny,
                        onPressed: () =>
                            _createPermission(PermissionType.morningToday),
                      ),
                      _PermissionButton(
                        text: 'Bugün akşam yokum',
                        icon: Icons.nights_stay,
                        onPressed: () =>
                            _createPermission(PermissionType.eveningToday),
                      ),
                      _PermissionButton(
                        text: 'Bugün gelmeyeceğim',
                        icon: Icons.cancel,
                        color: Colors.red,
                        onPressed: () =>
                            _createPermission(PermissionType.allToday),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 4,
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Yarın İçin İzinler',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PermissionButton(
                        text: 'Yarın sabah yokum',
                        icon: Icons.wb_sunny,
                        onPressed: () =>
                            _createPermission(PermissionType.morningTomorrow),
                      ),
                      _PermissionButton(
                        text: 'Yarın gelmeyeceğim',
                        icon: Icons.cancel,
                        color: Colors.red,
                        onPressed: () =>
                            _createPermission(PermissionType.allTomorrow),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 4,
            color: Color(0xFFE0E7FF),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tatil Aralığı',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _selectVacationDates,
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        vacationStartDate != null && vacationEndDate != null
                            ? '${_formatDate(vacationStartDate!)} - ${_formatDate(vacationEndDate!)}'
                            : 'Tatil tarihlerini seç',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFE0E7FF),
                        foregroundColor: Color(0xFF4338CA),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          vacationStartDate != null && vacationEndDate != null
                              ? () => _createPermission(PermissionType.vacation)
                              : null,
                      icon: const Icon(Icons.beach_access),
                      label: const Text('Tatil izni oluştur'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFE0E7FF),
                        foregroundColor: Color(0xFF4338CA),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Açıklama (İsteğe Bağlı)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _reasonController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'İzin sebebinizi yazabilirsiniz...',
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Aktif İzinlerim:',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<PermissionModel>>(
            stream: PermissionService.getUserPermissions(user.uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 48,
                          color: Colors.green.shade400,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Aktif izniniz bulunmuyor.',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: snapshot.data!.map((permission) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _getPermissionColor(permission.type),
                        child: Icon(
                          _getPermissionIcon(permission.type),
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        permission.typeDisplayName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_getPermissionDateText(permission)),
                          if (permission.reason != null)
                            Text(
                              'Sebep: ${permission.reason}',
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _cancelPermission(permission.id),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
  Future<void> _cancelPermission(String permissionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İzni İptal Et'),
        content: const Text('Bu izni iptal etmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hayır'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Evet'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final error = await PermissionService.cancelPermission(permissionId);
      if (mounted) {
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('İzin başarıyla iptal edildi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
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
    }
  }
  Color _getPermissionColor(PermissionType type) {
    switch (type) {
      case PermissionType.morningToday:
      case PermissionType.morningTomorrow:
        return Colors.orange;
      case PermissionType.eveningToday:
        return Colors.indigo;
      case PermissionType.allToday:
      case PermissionType.allTomorrow:
        return Colors.red;
      case PermissionType.vacation:
        return Color(0xFF6366F1);
    }
  }
  String _getPermissionDateText(PermissionModel permission) {
    if (permission.type == PermissionType.vacation) {
      return '${_formatDate(permission.startDate)} - ${_formatDate(permission.endDate!)}';
    } else {
      return _formatDate(permission.startDate);
    }
  }
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
class _PermissionButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? color;
  final VoidCallback? onPressed;
  const _PermissionButton({
    required this.text,
    required this.icon,
    this.color,
    this.onPressed,
  });
  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        color != null ? color!.withOpacity(0.2) : Colors.blue.shade100;
    final foregroundColor = color ?? Colors.blue.shade700;
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(text),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

// Updated


// Updated Again

