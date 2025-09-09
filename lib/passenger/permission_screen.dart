import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../service/permission_service.dart';
import '../service/user_session.dart';
import '../models/permission_model.dart';
class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});
  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}
class _PermissionScreenState extends State<PermissionScreen> {
  final user = FirebaseAuth.instance.currentUser!;
  String? userName;
  DateTime? vacationStartDate;
  DateTime? vacationEndDate;
  final TextEditingController _descriptionController = TextEditingController();
  List<PermissionModel> activePermissions = [];
  DateTime? selectedStartDate;
  DateTime? selectedEndDate;
  List<PermissionModel> filteredPermissions = [];
  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadActivePermissions();
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
  void _loadActivePermissions() {
    PermissionService.getUserPermissions(user.uid).listen((permissions) {
      if (mounted) {
        setState(() {
          activePermissions = permissions;
          if (filteredPermissions.isEmpty) {
            filteredPermissions = permissions;
          }
          _filterPermissionsByDateRange();
        });
      }
    });
  }
  void _filterPermissionsByDateRange() {
    if (selectedStartDate == null || selectedEndDate == null) {
      filteredPermissions = activePermissions;
    } else {
      final startDateOnly = DateTime(selectedStartDate!.year,
          selectedStartDate!.month, selectedStartDate!.day);
      final endDateOnly = DateTime(
          selectedEndDate!.year, selectedEndDate!.month, selectedEndDate!.day);
      filteredPermissions = activePermissions.where((permission) {
        final permissionStartOnly = DateTime(permission.startDate.year,
            permission.startDate.month, permission.startDate.day);
        final startInRange = permissionStartOnly
                .isAfter(startDateOnly.subtract(const Duration(days: 1))) &&
            permissionStartOnly
                .isBefore(endDateOnly.add(const Duration(days: 1)));
        if (permission.endDate != null) {
          final permissionEndOnly = DateTime(permission.endDate!.year,
              permission.endDate!.month, permission.endDate!.day);
          final endInRange = permissionEndOnly
                  .isAfter(startDateOnly.subtract(const Duration(days: 1))) &&
              permissionEndOnly
                  .isBefore(endDateOnly.add(const Duration(days: 1)));
          return startInRange || endInRange;
        }
        return startInRange;
      }).toList();
    }
    if (mounted) {
      setState(() {});
    }
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
    final error = await PermissionService.createPermissionWithRouteUpdate(
      userId: user.uid,
      userName: userName!,
      type: type,
      startDate: startDate,
      endDate: endDate,
      reason: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
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
            content: Text('İzin oluşturuldu ve rota otomatik güncellendi!'),
            backgroundColor: Colors.green,
          ),
        );
        _descriptionController.clear();
        setState(() {
          vacationStartDate = null;
          vacationEndDate = null;
        });
        _loadActivePermissions();
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
      await _createPermission(PermissionType.vacation);
    }
  }
  Future<void> _selectDateRangeForFilter() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: selectedStartDate != null && selectedEndDate != null
          ? DateTimeRange(start: selectedStartDate!, end: selectedEndDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        selectedStartDate = picked.start;
        selectedEndDate = picked.end;
      });
      _filterPermissionsByDateRange();
      await _generateRouteForDateRange();
    }
  }
  Future<void> _generateRouteForDateRange() async {
    if (selectedStartDate == null || selectedEndDate == null) return;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final regionId = userDoc.data()?['regionId'];
      if (regionId == null || UserSession.driverId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bölge veya şoför bilgisi bulunamadı'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      final result = await PermissionService.generateRouteForDateRange(
        driverId: UserSession.driverId!,
        regionId: regionId,
        startDate: selectedStartDate!,
        endDate: selectedEndDate!,
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_formatDate(selectedStartDate!)} - ${_formatDate(selectedEndDate!)} tarih aralığı için rotalar oluşturuldu!',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rota oluşturma hatası: $result'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rota oluşturma hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  void _clearDateFilter() {
    setState(() {
      selectedStartDate = null;
      selectedEndDate = null;
    });
    _filterPermissionsByDateRange();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tarih filtresi temizlendi'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 2),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.green.shade600,
                    Colors.green.shade700,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.shade200,
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.assignment,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'İzin Bildirimi',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Merhaba $userName',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Servis kullanmayacağınız zamanları bildirin',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildModernPermissionCard(
              title: 'Bugün İçin İzinler',
              color: Colors.orange.shade600,
              children: [
                _buildModernPermissionButton(
                  text: 'Sabah Servisi',
                  subtitle: 'Sabah servisini kullanmayacağım',
                  icon: Icons.wb_sunny,
                  color: Colors.orange.shade600,
                  onPressed: () =>
                      _createPermission(PermissionType.morningToday),
                ),
                _buildModernPermissionButton(
                  text: 'Akşam Servisi',
                  subtitle: 'Akşam servisini kullanmayacağım',
                  icon: Icons.nights_stay,
                  color: Colors.orange.shade600,
                  onPressed: () =>
                      _createPermission(PermissionType.eveningToday),
                ),
                _buildModernPermissionButton(
                  text: 'Tüm Gün',
                  subtitle: 'Bugün hiç servis kullanmayacağım',
                  icon: Icons.cancel,
                  color: Colors.orange.shade600,
                  onPressed: () => _createPermission(PermissionType.allToday),
                ),
              ],
            ),
            _buildModernPermissionCard(
              title: 'Yarın İçin İzinler',
              color: Colors.blue.shade600,
              children: [
                _buildModernPermissionButton(
                  text: 'Sabah Servisi',
                  subtitle: 'Yarın sabah servisini kullanmayacağım',
                  icon: Icons.wb_sunny,
                  color: Colors.blue.shade600,
                  onPressed: () =>
                      _createPermission(PermissionType.morningTomorrow),
                ),
                _buildModernPermissionButton(
                  text: 'Tüm Gün',
                  subtitle: 'Yarın hiç servis kullanmayacağım',
                  icon: Icons.cancel,
                  color: Colors.blue.shade600,
                  onPressed: () =>
                      _createPermission(PermissionType.allTomorrow),
                ),
              ],
            ),
            _buildModernPermissionCard(
              title: 'Tatil İzni',
              color: Color(0xFF6366F1),
              children: [
                _buildModernPermissionButton(
                  text: 'Tatil İzni',
                  subtitle: 'Birden fazla gün için izin al',
                  icon: Icons.beach_access,
                  color: Color(0xFF6366F1),
                  onPressed: _selectVacationDates,
                ),
              ],
            ),
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade200,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.note_add,
                            color: Colors.grey.shade600,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Açıklama (İsteğe Bağlı)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: TextField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'İzin sebebinizi belirtebilirsiniz...',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Colors.green.shade500, width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (activePermissions.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade200,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.red.shade50,
                            Colors.red
                                .shade100,
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.schedule,
                                  color: Colors.red.shade600,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Aktif İzinleriniz',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _selectDateRangeForFilter,
                                  icon: const Icon(Icons.date_range, size: 18),
                                  label: Text(
                                    selectedStartDate != null &&
                                            selectedEndDate != null
                                        ? '${_formatDate(selectedStartDate!)} - ${_formatDate(selectedEndDate!)}'
                                        : 'Tarih Aralığı Seç',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade50,
                                    foregroundColor: Colors.red.shade700,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(
                                          color: Colors.red.shade200),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (selectedStartDate != null &&
                                  selectedEndDate != null)
                                IconButton(
                                  onPressed: _clearDateFilter,
                                  icon: Icon(Icons.clear,
                                      color: Colors.red.shade600, size: 18),
                                  tooltip: 'Filtreyi Temizle',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.red.shade50,
                                    padding: const EdgeInsets.all(8),
                                  ),
                                ),
                            ],
                          ),
                          if (selectedStartDate != null &&
                              selectedEndDate != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Seçilen tarih aralığında ${filteredPermissions.length} izin bulundu',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade600,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: filteredPermissions.map((permission) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.red
                                  .shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.shade200,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    _getPermissionIcon(permission.type),
                                    color: Colors.red.shade600,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        permission.typeDisplayName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _getPermissionDateText(permission),
                                        style: TextStyle(
                                          color: Colors.red.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (permission.description?.isNotEmpty ==
                                          true) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          permission.description!,
                                          style: TextStyle(
                                            color: Colors.red.shade500,
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      _cancelPermission(permission.id),
                                  icon: Icon(
                                    Icons.cancel,
                                    color: Colors.red.shade600,
                                    size: 20,
                                  ),
                                  tooltip: 'İzni İptal Et',
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  Widget _buildModernPermissionCard({
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.1),
                  color.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.access_time,
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildModernPermissionButton({
    required String text,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.08),
                  color.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: color.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: color,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: color.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
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
      await PermissionService.cancelPermissionWithRouteUpdate(
          permissionId, user.uid, UserSession.driverId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İzin iptal edildi ve rota güncellendi!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        _loadActivePermissions();
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
  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }
}

// Updated

