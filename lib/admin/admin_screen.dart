import 'package:flutter/material.dart';
import '../service/auth_service.dart';
import '../view/login_screen.dart';
import '../widget/common_loading_screen.dart';
import 'driver_management_screen.dart';
import 'stop_management_screen.dart';
import 'region_management_screen.dart';
import 'employee_management_screen.dart';
import 'service_assignment_screen.dart';
import 'live_map_screen.dart';
import 'driver_tracking_screen.dart';
import 'region_live_tracking_screen.dart';
import 'messages_management_screen.dart';
import 'permissions_management_screen.dart';
import 'notification_management_screen.dart';
import '../utils/coordinate_fixer.dart';
import '../utils/app_colors.dart';
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.admin_panel_settings,
                size: 24,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Admin Paneli'),
          ],
        ),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: Container(
        width: MediaQuery.of(context).size.width * 0.75,
        child: Drawer(
          child: SafeArea(
            child: Column(
              children: [
                Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.blue.shade600,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.admin_panel_settings,
                            size: 32,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Admin Paneli',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Yönetim Sistemi',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Aktif',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          _buildSectionHeader('Kullanıcı Yönetimi'),
                          _buildMenuItem(
                            icon: Icons.drive_eta,
                            title: 'Şoför Yönetimi',
                            onTap: () => _navigateTo(
                              context,
                              const DriverManagementScreen(),
                            ),
                          ),
                          _buildMenuItem(
                            icon: Icons.group,
                            title: 'Kullanıcı Yönetimi',
                            onTap: () => _navigateTo(
                              context,
                              const EmployeeManagementScreen(),
                            ),
                          ),
                          const Divider(height: 24, indent: 16, endIndent: 16),
                          _buildSectionHeader('Sistem Yönetimi'),
                          _buildMenuItem(
                            icon: Icons.location_on,
                            title: 'Durak Yönetimi',
                            onTap: () => _navigateTo(
                                context, const StopManagementScreen()),
                          ),
                          _buildMenuItem(
                            icon: Icons.place,
                            title: 'Bölge Yönetimi',
                            onTap: () => _navigateTo(
                              context,
                              const RegionManagementScreen(),
                            ),
                          ),
                          _buildMenuItem(
                            icon: Icons.assignment,
                            title: 'Servis Atama',
                            onTap: () => _navigateTo(
                              context,
                              const ServiceAssignmentScreen(),
                            ),
                          ),
                          _buildMenuItem(
                            icon: Icons.auto_awesome,
                            title: 'Otomatik Rota',
                            subtitle:
                                'Yolcu adreslerine göre otomatik hat oluşturma',
                            onTap: () => _showAutoRouteInfo(context),
                          ),
                          _buildMenuItem(
                            icon: Icons.gps_fixed,
                            title: 'Koordinat Düzeltme',
                            subtitle: 'Durak koordinatlarını otomatik düzelt',
                            onTap: () => _showCoordinateFixDialog(context),
                          ),
                          const Divider(height: 24, indent: 16, endIndent: 16),
                          _buildSectionHeader('İletişim & İzinler'),
                          _buildMenuItem(
                            icon: Icons.message,
                            title: 'Mesaj Yönetimi',
                            onTap: () => _navigateTo(
                              context,
                              const MessagesManagementScreen(),
                            ),
                          ),
                          _buildMenuItem(
                            icon: Icons.notifications,
                            title: 'Bildirim Yönetimi',
                            onTap: () => _navigateTo(
                              context,
                              const NotificationManagementScreen(),
                            ),
                          ),
                          _buildMenuItem(
                            icon: Icons.event_busy,
                            title: 'İzin Yönetimi',
                            onTap: () => _navigateTo(
                              context,
                              const PermissionsManagementScreen(),
                            ),
                          ),
                          const Divider(height: 24, indent: 16, endIndent: 16),
                          _buildSectionHeader('Takip & Monitoring'),
                          _buildMenuItem(
                            icon: Icons.directions_car,
                            title: 'Canlı Harita',
                            onTap: () => _navigateTo(
                                context, const EnhancedLiveMapScreen()),
                          ),
                          _buildMenuItem(
                            icon: Icons.track_changes,
                            title: 'Şoför Takibi',
                            onTap: () => _navigateTo(
                                context, const DriverTrackingScreen()),
                          ),
                          _buildMenuItem(
                            icon: Icons.location_city,
                            title: 'Bölge Canlı Takip',
                            onTap: () => _navigateTo(
                              context,
                              const RegionLiveTrackingScreen(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Material(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _logout(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.logout,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Çıkış Yap',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.blue.shade200,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.admin_panel_settings,
                            size: 32,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hoş Geldiniz!',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                Text(
                                  'Servis Yönetim Sistemi',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.shade200,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              color: Colors.blue.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Otomatik rota sistemi aktif - Yolcu adresleri otomatik olarak ana yol duraklarına dönüştürülüyor',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Hızlı İşlemler',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    children: [
                      _buildQuickActionCard(
                        context,
                        icon: Icons.drive_eta,
                        title: 'Şoför Yönetimi',
                        subtitle: 'Şoför bilgileri',
                        color: Colors.green,
                        onTap: () => _navigateTo(
                          context,
                          const DriverManagementScreen(),
                        ),
                      ),
                      _buildQuickActionCard(
                        context,
                        icon: Icons.message,
                        title: 'Mesaj Yönetimi',
                        subtitle: 'İletişim sistemi',
                        color: Colors.blue,
                        onTap: () => _navigateTo(
                          context,
                          const MessagesManagementScreen(),
                        ),
                      ),
                      _buildQuickActionCard(
                        context,
                        icon: Icons.location_city,
                        title: 'Bölge Canlı Takip',
                        subtitle: 'Gerçek zamanlı',
                        color: Colors.orange,
                        onTap: () => _navigateTo(
                          context,
                          const RegionLiveTrackingScreen(),
                        ),
                      ),
                      _buildQuickActionCard(
                        context,
                        icon: Icons.event_busy,
                        title: 'İzin Yönetimi',
                        subtitle: 'İzin takibi',
                        color: Color(0xFF6366F1),
                        onTap: () => _navigateTo(
                          context,
                          const PermissionsManagementScreen(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildQuickActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textDark,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
  void _showAutoRouteInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.blue, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Otomatik Rota Sistemi',
                style: TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Otomatik rota sistemi şu özellikleri sağlar:',
                style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: AppColors.textDark),
              ),
              const SizedBox(height: 12),
              const Text(
                '• Yolcu adresleri otomatik olarak ana yol üzerindeki duraklara dönüştürülür',
                style: TextStyle(fontSize: 12, color: AppColors.textDark),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Şoför konumuna göre en optimal rota oluşturulur',
                style: TextStyle(fontSize: 12, color: AppColors.textDark),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Manuel hat tanımlama gereksizdir',
                style: TextStyle(fontSize: 12, color: AppColors.textDark),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Sistem gerçek zamanlı olarak güncellenir',
                style: TextStyle(fontSize: 12, color: AppColors.textDark),
              ),
              const SizedBox(height: 16),
              Text(
                'Bu sistem sayesinde manuel hat yönetimi kaldırılmış ve tüm işlemler otomatikleştirilmiştir.',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: AppColors.textDark,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anladım'),
          ),
        ],
      ),
    );
  }
  void _showCoordinateFixDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.gps_fixed, color: Colors.orange, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Koordinat Düzeltme',
                style: TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bu işlem şunları yapar:',
                style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: Colors.black87),
              ),
              const SizedBox(height: 12),
              const Text(
                '• Geçersiz koordinatları (0.0, 0.0) tespit eder',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Adres bilgisini kullanarak gerçek koordinatları alır',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Durak koordinatlarını otomatik günceller',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              const Text(
                '• Rota oluşturma sorunlarını çözer',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning,
                        color: Colors.orange.shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu işlem internet bağlantısı gerektirir ve birkaç dakika sürebilir.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startCoordinateFix(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Başlat'),
          ),
        ],
      ),
    );
  }
  void _startCoordinateFix(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SimpleLoadingIndicator(
              message: 'Koordinatlar düzeltiliyor...',
              size: 48,
            ),
            SizedBox(height: 8),
            Text(
              'Bu işlem birkaç dakika sürebilir',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
    try {
      await CoordinateFixer.fixAllStopCoordinates();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Koordinat düzeltme işlemi tamamlandı!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Hata: $e'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.blue.shade700,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textDark,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: AppColors.textDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }
  void _logout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Çıkış yapmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
    if (shouldLogout == true) {
      await AuthService().signOut();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }
}
