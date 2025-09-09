import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'service_tracking.dart';
import 'enhanced_service_tracking.dart';
import '../service/user_session.dart';
import '../service/enhanced_tracking_service.dart';
import '../view/login_screen.dart';
import 'distance_alert.dart';
import '../service/auto_stop_service.dart';
import 'dart:math' as math;
class HomeOverview extends StatelessWidget {
  const HomeOverview({super.key});
  Future<Map<String, dynamic>> loadUserData() async {
    try {
      print('=== HOME OVERVIEW loadUserData başladı ===');
      print('UserSession.userId: ${UserSession.userId}');
      print('UserSession.regionName: ${UserSession.regionName}');
      print('UserSession.driverName: ${UserSession.driverName}');
      String regionName = UserSession.regionName ?? 'Atanmamış';
      String driverName = UserSession.driverName ?? 'Atanmamış';
      print(
          'Başlangıç değerleri - regionName: $regionName, driverName: $driverName');
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(UserSession.userId!)
          .get();
      final userData = userDoc.data() ?? {};
      print('Users koleksiyonundan alınan veri: $userData');
      if (regionName == 'Atanmamış' || driverName == 'Atanmamış') {
        print('UserSession\'da eksik bilgi var, Firestore\'dan yükleniyor...');
        final passengerDoc = await FirebaseFirestore.instance
            .collection('passengers')
            .doc(UserSession.userId!)
            .get();
        Map<String, dynamic>? passengerData;
        if (passengerDoc.exists) {
          passengerData = passengerDoc.data()!;
          print('Passengers koleksiyonundan alınan veri: $passengerData');
          if (userDoc.exists) {
            final userDataFromUsers = userDoc.data()!;
            bool needsUpdate = false;
            Map<String, dynamic> updateData = {};
            if (passengerData['regionId'] == null &&
                userDataFromUsers['regionId'] != null) {
              updateData['regionId'] = userDataFromUsers['regionId'];
              passengerData['regionId'] = userDataFromUsers['regionId'];
              needsUpdate = true;
              print(
                  'RegionId passengers koleksiyonuna ekleniyor: ${userDataFromUsers['regionId']}');
            }
            if (passengerData['driverId'] == null &&
                userDataFromUsers['driverId'] != null) {
              updateData['driverId'] = userDataFromUsers['driverId'];
              passengerData['driverId'] = userDataFromUsers['driverId'];
              needsUpdate = true;
              print(
                  'DriverId passengers koleksiyonuna ekleniyor: ${userDataFromUsers['driverId']}');
            }
            if (needsUpdate) {
              updateData['updatedAt'] = FieldValue.serverTimestamp();
              await FirebaseFirestore.instance
                  .collection('passengers')
                  .doc(UserSession.userId!)
                  .update(updateData);
              print('Passengers koleksiyonu güncellendi: $updateData');
            }
          }
        } else {
          print(
              'Passengers koleksiyonunda veri yok, users koleksiyonundan oluşturuluyor...');
          if (userDoc.exists) {
            final userDataFromUsers = userDoc.data()!;
            passengerData = {
              'regionId': userDataFromUsers['regionId'],
              'driverId': userDataFromUsers['driverId'],
              'name': userDataFromUsers['name'],
              'email': userDataFromUsers['email'],
            };
            print('Users\'dan alınan passenger verisi: $passengerData');
            try {
              await FirebaseFirestore.instance
                  .collection('passengers')
                  .doc(UserSession.userId!)
                  .set({
                'name': userDataFromUsers['name'] ?? '',
                'email': userDataFromUsers['email'] ?? '',
                'regionId': userDataFromUsers['regionId'] ?? '',
                'driverId': userDataFromUsers['driverId'] ?? '',
                'userId': UserSession.userId,
                'phone': userDataFromUsers['phone'] ?? '',
                'address': userDataFromUsers['address'] ?? '',
                'distance': userDataFromUsers['distance'] ?? 0.0,
                'profileImageUrl': userDataFromUsers['profileImageUrl'] ??
                    userDataFromUsers['photoUrl'] ??
                    '',
                'isActive': true,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
              print('Passengers koleksiyonu başarıyla oluşturuldu');
            } catch (e) {
              print('Passengers koleksiyonu oluşturulurken hata: $e');
            }
          }
        }
        if (passengerData != null) {
          print(
              'Passenger data mevcut, bölge ve şoför bilgileri kontrol ediliyor...');
          print('passengerData[regionId]: ${passengerData['regionId']}');
          print('passengerData[driverId]: ${passengerData['driverId']}');
          if (regionName == 'Atanmamış' &&
              passengerData['regionId'] != null &&
              passengerData['regionId'].toString().isNotEmpty) {
            print(
                'Bölge bilgisi yükleniyor... regionId: ${passengerData['regionId']}');
            try {
              final regionDoc = await FirebaseFirestore.instance
                  .collection('regions')
                  .doc(passengerData['regionId'])
                  .get();
              if (regionDoc.exists) {
                regionName = regionDoc.data()?['name'] ?? 'Atanmamış';
                UserSession.regionName = regionName;
                UserSession.regionId = passengerData['regionId'];
                print('Bölge bilgisi yüklendi: $regionName');
              } else {
                regionName = 'Bölge Bulunamadı';
                UserSession.regionName = regionName;
                print('Bölge dokümanı bulunamadı');
              }
            } catch (e) {
              print('Bölge bilgisi yüklenirken hata: $e');
              regionName = 'Bölge Yükleme Hatası';
              UserSession.regionName = regionName;
            }
          } else {
            print(
                'Bölge bilgisi atlanıyor - regionName: $regionName, regionId: ${passengerData['regionId']}');
          }
          if (driverName == 'Atanmamış' &&
              passengerData['driverId'] != null &&
              passengerData['driverId'].toString().isNotEmpty) {
            print(
                'Şoför bilgisi yükleniyor... driverId: ${passengerData['driverId']}');
            try {
              final driverDoc = await FirebaseFirestore.instance
                  .collection('drivers')
                  .doc(passengerData['driverId'])
                  .get();
              if (driverDoc.exists) {
                final driverData = driverDoc.data()!;
                driverName = driverData['name'] ?? 'Atanmamış';
                UserSession.driverName = driverName;
                UserSession.driverId = passengerData['driverId'];
                UserSession.vehiclePlate = driverData['vehiclePlate'] ??
                    driverData['plate'] ??
                    'Atanmamış';
                print('Şoför bilgisi yüklendi: $driverName');
              } else {
                driverName = 'Şoför Bulunamadı';
                UserSession.driverName = driverName;
                print('Şoför dokümanı bulunamadı');
              }
            } catch (e) {
              print('Şoför bilgisi yüklenirken hata: $e');
              driverName = 'Şoför Yükleme Hatası';
              UserSession.driverName = driverName;
            }
          } else {
            print(
                'Şoför bilgisi atlanıyor - driverName: $driverName, driverId: ${passengerData['driverId']}');
          }
        } else {
          print('Passenger data null');
        }
      } else {
        print('UserSession\'da bilgiler mevcut, Firestore sorgusu atlandı');
      }
      final result = {
        ...userData,
        'regionName': regionName,
        'driverName': driverName
      };
      print('Final sonuç: $result');
      print('=== HOME OVERVIEW loadUserData tamamlandı ===');
      return result;
    } catch (e) {
      print('loadUserData genel hata: $e');
      return {'regionName': 'Yükleme Hatası', 'driverName': 'Yükleme Hatası'};
    }
  }
  Future<Map<String, dynamic>?> _getServiceStatus() async {
    try {
      return await EnhancedTrackingService.getServiceStatusForPassenger(
        UserSession.userId!,
        UserSession.regionId ?? '',
      );
    } catch (e) {
      print('Servis durumu alınırken hata: $e');
      return null;
    }
  }
  String _getCleanRegionName(String? regionName) {
    if (regionName == null || regionName.isEmpty) return 'Atanmamış';
    if (regionName.startsWith('{') && regionName.contains('"name"')) {
      try {
        final nameMatch =
            RegExp(r'"name"\s*:\s*"([^"]*)"').firstMatch(regionName);
        if (nameMatch != null) {
          return nameMatch.group(1) ?? regionName;
        }
      } catch (e) {
        print('JSON parse hatası: $e');
      }
    }
    final knownRegions = {
      'Danışment': 'Danışment',
      'Merkez': 'Merkez',
      'Keçiören': 'Keçiören',
      'Çankaya': 'Çankaya',
      'Mamak': 'Mamak',
      'Sincan': 'Sincan',
      'Etimesgut': 'Etimesgut',
      'Yenimahalle': 'Yenimahalle',
      'Gölbaşı': 'Gölbaşı',
      'Pursaklar': 'Pursaklar',
      'Altındağ': 'Altındağ',
      'Akyurt': 'Akyurt',
      'Ayaş': 'Ayaş',
      'Bala': 'Bala',
      'Beypazarı': 'Beypazarı',
      'Çamlıdere': 'Çamlıdere',
      'Çubuk': 'Çubuk',
      'Elmadağ': 'Elmadağ',
      'Güdül': 'Güdül',
      'Haymana': 'Haymana',
      'Kalecik': 'Kalecik',
      'Kızılcahamam': 'Kızılcahamam',
      'Nallıhan': 'Nallıhan',
      'Polatlı': 'Polatlı',
      'Şereflikoçhisar': 'Şereflikoçhisar',
    };
    for (final region in knownRegions.keys) {
      if (regionName.toLowerCase().contains(region.toLowerCase())) {
        return knownRegions[region]!;
      }
    }
    return regionName;
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: FutureBuilder<Map<String, dynamic>>(
        future: loadUserData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Veriler yükleniyor...'),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Hata: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const HomeOverview()),
                      );
                    },
                    child: const Text('Tekrar Dene'),
                  ),
                ],
              ),
            );
          }
          final userData = snapshot.data ?? {};
          final regionName = _getCleanRegionName(userData['regionName']);
          final driverName = userData['driverName'] ?? 'Atanmamış';
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 200,
                floating: false,
                pinned: true,
                backgroundColor: Colors.blue.shade600,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text(
                    'Servis Takip',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.blue.shade600,
                          Colors.blue.shade800,
                        ],
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.directions_bus,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      UserSession.clear();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                              builder: (context) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    },
                    icon: const Icon(Icons.logout, color: Colors.white),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
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
                                    color: Colors.blue.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.blue.shade600,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Hoş Geldiniz',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      Text(
                                        userData['name'] ?? 'Kullanıcı',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            const Divider(),
                            const SizedBox(height: 16),
                            _buildInfoRow(
                                'Bölge', regionName, Icons.location_on),
                            _buildInfoRow(
                                'Şoför', driverName, Icons.person_pin),
                            if (UserSession.vehiclePlate != null &&
                                UserSession.vehiclePlate != 'Atanmamış')
                              _buildInfoRow('Plaka', UserSession.vehiclePlate!,
                                  Icons.directions_car),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      FutureBuilder<Map<String, dynamic>?>(
                        future: _getServiceStatus(),
                        builder: (context, serviceSnapshot) {
                          final serviceStatus = serviceSnapshot.data;
                          final isServiceActive =
                              serviceStatus?['isActive'] == true;
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
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
                                        color: isServiceActive
                                            ? Colors.green.shade100
                                            : Colors.red.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        isServiceActive
                                            ? Icons.directions_bus
                                            : Icons.bus_alert,
                                        color: isServiceActive
                                            ? Colors.green.shade600
                                            : Colors.red.shade600,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Servis Durumu',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          Text(
                                            isServiceActive ? 'Aktif' : 'Pasif',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: isServiceActive
                                                  ? Colors.green.shade600
                                                  : Colors.red.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (isServiceActive &&
                                    serviceStatus != null) ...[
                                  const SizedBox(height: 20),
                                  const Divider(),
                                  const SizedBox(height: 16),
                                  if (serviceStatus['currentStop'] != null)
                                    _buildServiceInfoRow(
                                      'Mevcut Durak',
                                      serviceStatus['currentStop']['address'],
                                      Icons.location_on,
                                      Colors.orange,
                                    ),
                                  if (serviceStatus['nextStop'] != null)
                                    _buildServiceInfoRow(
                                      'Sonraki Durak',
                                      serviceStatus['nextStop']['address'],
                                      Icons.flag,
                                      Colors.red,
                                    ),
                                  FutureBuilder<double?>(
                                    future: _calculateEstimatedArrival(
                                        serviceStatus),
                                    builder: (context, arrivalSnapshot) {
                                      if (arrivalSnapshot.hasData &&
                                          arrivalSnapshot.data != null) {
                                        final minutes =
                                            arrivalSnapshot.data!.round();
                                        return _buildServiceInfoRow(
                                          'Tahmini Varış',
                                          '$minutes dakika',
                                          Icons.access_time,
                                          Colors.blue,
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Hızlı Erişim',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildQuickActionCard(
                              context,
                              'Gelişmiş Takip',
                              'Harita ve detaylı bilgiler',
                              Icons.map,
                              Colors.blue,
                              () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        EnhancedServiceTracking(
                                      passengerId: UserSession.userId!,
                                      regionId: UserSession.regionId ?? '',
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickActionCard(
                              context,
                              'Canlı Takip',
                              'Basit konum takibi',
                              Icons.location_on,
                              Colors.green,
                              () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const ServiceTracking(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildQuickActionCard(
                              context,
                              'Mesafe Uyarısı',
                              'Yakınlık bildirimleri',
                              Icons.notifications,
                              Colors.orange,
                              () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const DistanceAlertScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickActionCard(
                              context,
                              'Mesajlar',
                              'Şoför ile iletişim',
                              Icons.message,
                              Color(0xFF6366F1),
                              () {
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
  Future<double?> _calculateEstimatedArrival(
      Map<String, dynamic> serviceStatus) async {
    try {
      if (serviceStatus['driverLocation'] == null) return null;
      final trackingService = EnhancedTrackingService();
      return 15.0;
    } catch (e) {
      print('Tahmini varış süresi hesaplama hatası: $e');
      return null;
    }
  }
  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue.shade600, size: 20),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildServiceInfoRow(
      String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildQuickActionCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Updated


// Updated Again

