import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../service/user_session.dart';
import '../service/simple_stop_service.dart';
import '../service/enhanced_stop_management_service.dart';
import '../service/geocoding_service.dart';
import '../service/cache_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import '../service/avatar_marker_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  String? photoUrl;
  String regionName = 'Yükleniyor...';
  String driverName = 'Yükleniyor...';
  String vehiclePlate = 'Yükleniyor...';
  bool isLoading = true;
  bool isEditing = false;
  bool _testModeEnabled = false;
  @override
  void initState() {
    super.initState();
    _loadProfile();
    try {
      _testModeEnabled =
          CacheService.getCache<bool>('passenger_test_mode') ?? false;
    } catch (_) {
      _testModeEnabled = false;
    }
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      final String? uid =
          UserSession.userId ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        if (mounted) {
          setState(() => isLoading = false);
        }
        return;
      }
      if (UserSession.userId == null) {
        UserSession.userId = uid;
      }
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        _nameController.text =
            (userData['name'] ?? userData['displayName'] ?? '').toString();
        _emailController.text = (userData['email'] ?? '').toString();
        _phoneController.text =
            (userData['phone'] ?? userData['phoneNumber'] ?? '').toString();
        _addressController.text = (userData['address'] ?? '').toString();
        UserSession.userName ??= _nameController.text;
        UserSession.userEmail ??= _emailController.text;
        UserSession.regionId ??= userData['regionId'];
        UserSession.driverId ??= userData['driverId'];
        if (UserSession.photoUrl != null && UserSession.photoUrl!.isNotEmpty) {
          photoUrl = UserSession.photoUrl!;
        } else if (userData['photoUrl'] != null) {
          photoUrl = userData['photoUrl'];
          UserSession.photoUrl = userData['photoUrl'];
        } else if (userData['profileImageUrl'] != null) {
          photoUrl = userData['profileImageUrl'];
          UserSession.photoUrl = userData['profileImageUrl'];
        }
      }
      if (UserSession.regionName != null &&
          UserSession.regionName!.isNotEmpty) {
        if (mounted) {
          setState(() {
            regionName = _shortenRegionName(
                _getCleanRegionName(UserSession.regionName!));
          });
        }
      } else {
        final String? regionIdCandidate =
            UserSession.regionId ?? (userDoc.data()?['regionId'] as String?);
        if (regionIdCandidate != null && regionIdCandidate.isNotEmpty) {
          try {
            final regionDoc = await FirebaseFirestore.instance
                .collection('regions')
                .doc(regionIdCandidate)
                .get();
            if (regionDoc.exists && mounted) {
              final fullRegionName = regionDoc.data()?['name'] ?? 'Atanmamış';
              setState(() {
                regionName =
                    _shortenRegionName(_getCleanRegionName(fullRegionName));
              });
              UserSession.regionName = fullRegionName;
            } else if (mounted) {
              setState(() => regionName = 'Atanmamış');
              UserSession.regionName = 'Atanmamış';
            }
          } catch (_) {
            if (mounted) setState(() => regionName = 'Atanmamış');
            UserSession.regionName = 'Atanmamış';
          }
        } else {
          if (mounted) setState(() => regionName = 'Atanmamış');
        }
      }
      if (UserSession.driverName != null &&
          UserSession.driverName!.isNotEmpty) {
        if (mounted) setState(() => driverName = UserSession.driverName!);
      } else {
        final String? driverIdCandidate =
            UserSession.driverId ?? (userDoc.data()?['driverId'] as String?);
        if (driverIdCandidate != null && driverIdCandidate.isNotEmpty) {
          try {
            final driverDoc = await FirebaseFirestore.instance
                .collection('drivers')
                .doc(driverIdCandidate)
                .get();
            if (driverDoc.exists && mounted) {
              final d = driverDoc.data()!;
              setState(() => driverName = d['name'] ?? 'Atanmamış');
              UserSession.driverName = d['name'] ?? UserSession.driverName;
            } else if (mounted) {
              setState(() => driverName = 'Atanmamış');
            }
          } catch (_) {
            if (mounted) setState(() => driverName = 'Atanmamış');
          }
        } else {
          if (mounted) setState(() => driverName = 'Atanmamış');
        }
      }
      if (UserSession.vehiclePlate != null &&
          UserSession.vehiclePlate!.isNotEmpty) {
        if (mounted) setState(() => vehiclePlate = UserSession.vehiclePlate!);
      } else {
        final String? driverIdCandidate =
            UserSession.driverId ?? (userDoc.data()?['driverId'] as String?);
        if (driverIdCandidate != null && driverIdCandidate.isNotEmpty) {
          try {
            final driverDoc = await FirebaseFirestore.instance
                .collection('drivers')
                .doc(driverIdCandidate)
                .get();
            if (driverDoc.exists && mounted) {
              final d = driverDoc.data()!;
              final raw = d['vehiclePlate'] ?? d['plate'] ?? '';
              final cleaned = _getCleanVehiclePlate(raw.toString());
              setState(() =>
                  vehiclePlate = cleaned.isNotEmpty ? cleaned : 'Atanmamış');
              UserSession.vehiclePlate = cleaned;
            } else if (mounted) {
              setState(() => vehiclePlate = 'Atanmamış');
            }
          } catch (_) {
            if (mounted) setState(() => vehiclePlate = 'Atanmamış');
          }
        } else {
          if (mounted) setState(() => vehiclePlate = 'Atanmamış');
        }
      }
      if (regionName == 'Atanmamış' ||
          driverName == 'Atanmamış' ||
          vehiclePlate == 'Atanmamış') {
        final passengerDoc = await FirebaseFirestore.instance
            .collection('passengers')
            .doc(uid)
            .get();
        Map<String, dynamic>? passengerData;
        if (passengerDoc.exists) {
          passengerData = passengerDoc.data()!;
          _nameController.text = (_nameController.text.isEmpty)
              ? (passengerData['name'] ?? _nameController.text)
              : _nameController.text;
          _emailController.text = (_emailController.text.isEmpty)
              ? (passengerData['email'] ?? _emailController.text)
              : _emailController.text;
          _phoneController.text = (_phoneController.text.isEmpty)
              ? (passengerData['phone'] ?? _phoneController.text)
              : _phoneController.text;
          _addressController.text =
              passengerData['address'] ?? _addressController.text;
        } else {
          print(
              'Passengers koleksiyonunda veri yok, users koleksiyonundan oluşturuluyor...');
          if (userDoc.exists) {
            final userDataFromUsers = userDoc.data()!;
            try {
              await FirebaseFirestore.instance
                  .collection('passengers')
                  .doc(uid)
                  .set({
                'name': userDataFromUsers['name'] ?? '',
                'email': userDataFromUsers['email'] ?? '',
                'regionId': userDataFromUsers['regionId'] ?? '',
                'driverId': userDataFromUsers['driverId'] ?? '',
                'userId': uid,
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
              passengerData = {
                'regionId': userDataFromUsers['regionId'],
                'driverId': userDataFromUsers['driverId'],
                'name': userDataFromUsers['name'],
                'email': userDataFromUsers['email'],
                'address': userDataFromUsers['address'],
              };
              _addressController.text =
                  passengerData['address'] ?? _addressController.text;
              print('Passengers koleksiyonu başarıyla oluşturuldu');
            } catch (e) {
              print('Passengers koleksiyonu oluşturulurken hata: $e');
              passengerData = {
                'regionId': userDataFromUsers['regionId'],
                'driverId': userDataFromUsers['driverId'],
                'name': userDataFromUsers['name'],
                'email': userDataFromUsers['email'],
                'address': userDataFromUsers['address'],
              };
            }
          }
        }
        if (passengerData != null) {
          if (regionName == 'Atanmamış' &&
              passengerData['regionId'] != null &&
              passengerData['regionId'].toString().isNotEmpty) {
            try {
              final regionDoc = await FirebaseFirestore.instance
                  .collection('regions')
                  .doc(passengerData['regionId'])
                  .get();
              if (regionDoc.exists && mounted) {
                final fullRegionName = regionDoc.data()?['name'] ?? 'Atanmamış';
                setState(() {
                  regionName =
                      _shortenRegionName(_getCleanRegionName(fullRegionName));
                });
                UserSession.regionName = fullRegionName;
              } else {
                print('Bölge belgesi bulunamadı: ${passengerData['regionId']}');
                if (mounted) {
                  setState(() {
                    regionName = 'Atanmamış';
                  });
                }
                UserSession.regionName = 'Atanmamış';
              }
            } catch (e) {
              print('Bölge bilgisi yüklenirken hata: $e');
              if (mounted) {
                setState(() {
                  regionName = 'Atanmamış';
                });
              }
              UserSession.regionName = 'Atanmamış';
            }
          } else if (regionName == 'Atanmamış' && mounted) {
            setState(() {
              regionName = 'Atanmamış';
            });
            UserSession.regionName = 'Atanmamış';
          }
          if ((driverName == 'Atanmamış' || vehiclePlate == 'Atanmamış') &&
              passengerData['driverId'] != null &&
              passengerData['driverId'].toString().isNotEmpty) {
            try {
              final driverDoc = await FirebaseFirestore.instance
                  .collection('drivers')
                  .doc(passengerData['driverId'])
                  .get();
              if (driverDoc.exists && mounted) {
                final driverData = driverDoc.data()!;
                final newDriverName = driverData['name'] ?? 'Atanmamış';
                final rawVehiclePlate = driverData['vehiclePlate'] ??
                    driverData['plate'] ??
                    'Atanmamış';
                final newVehiclePlate = _getCleanVehiclePlate(rawVehiclePlate);
                setState(() {
                  driverName = newDriverName;
                  vehiclePlate = newVehiclePlate;
                });
                UserSession.driverName = newDriverName;
                UserSession.vehiclePlate = newVehiclePlate;
              } else {
                print('Şoför belgesi bulunamadı: ${passengerData['driverId']}');
                if (mounted) {
                  setState(() {
                    driverName = 'Atanmamış';
                    vehiclePlate = 'Atanmamış';
                  });
                }
                UserSession.driverName = 'Atanmamış';
                UserSession.vehiclePlate = 'Atanmamış';
              }
            } catch (e) {
              print('Şoför bilgisi yüklenirken hata: $e');
              if (mounted) {
                setState(() {
                  driverName = 'Atanmamış';
                  vehiclePlate = 'Atanmamış';
                });
              }
              UserSession.driverName = 'Atanmamış';
              UserSession.vehiclePlate = 'Atanmamış';
            }
          } else if ((driverName == 'Atanmamış' ||
                  vehiclePlate == 'Atanmamış') &&
              mounted) {
            setState(() {
              driverName = 'Atanmamış';
              vehiclePlate = 'Atanmamış';
            });
            UserSession.driverName = 'Atanmamış';
            UserSession.vehiclePlate = 'Atanmamış';
          }
        }
      }
    } catch (e) {
      print('Profil yükleme hatası: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  String _shortenRegionName(String regionName) {
    List<String> words = regionName.trim().split(' ');
    if (words.isNotEmpty) {
      return words[0];
    }
    return regionName;
  }

  String _getCleanRegionName(String regionName) {
    if (regionName.contains('{') && regionName.contains('}')) {
      try {
        if (regionName.contains('"data"')) {
          RegExp dataRegex = RegExp(r'"data"\s*:\s*"([^"]+)"');
          Match? match = dataRegex.firstMatch(regionName);
          if (match != null) {
            return match.group(1) ?? 'Atanmamış';
          }
        }
        return 'Atanmamış';
      } catch (e) {
        return 'Atanmamış';
      }
    }
    return regionName;
  }

  String _getCleanVehiclePlate(String plate) {
    if (plate.contains('{') && plate.contains('}')) {
      try {
        if (plate.contains('"data"')) {
          RegExp dataRegex = RegExp(r'"data"\s*:\s*"([^"]+)"');
          Match? match = dataRegex.firstMatch(plate);
          if (match != null) {
            return match.group(1) ?? 'Atanmamış';
          }
        }
        RegExp plateRegex = RegExp(r'[0-9]{2}[A-Z]{1,3}[0-9]{1,4}');
        Match? match = plateRegex.firstMatch(plate);
        if (match != null) {
          return match.group(0) ?? 'Atanmamış';
        }
        return 'Atanmamış';
      } catch (e) {
        return 'Atanmamış';
      }
    }
    return plate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Builder(builder: (context) {
              if (_nameController.text.isEmpty &&
                  (UserSession.userName ?? '').isNotEmpty) {
                _nameController.text = UserSession.userName!;
              }
              if (_emailController.text.isEmpty &&
                  (UserSession.userEmail ?? '').isNotEmpty) {
                _emailController.text = UserSession.userEmail!;
              }
              return const SizedBox.shrink();
            }),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue.shade500,
                    Colors.blue.shade600,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  if (!isEditing)
                    Align(
                      alignment: Alignment.topRight,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (mounted) setState(() => isEditing = true);
                        },
                        icon: Icon(
                          Icons.edit_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Düzenle',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: OutlinedButton.styleFrom(
                          side:
                              BorderSide(color: Colors.white.withOpacity(0.6)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: isEditing ? _pickImage : null,
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 3,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 55,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            backgroundImage: photoUrl != null
                                ? NetworkImage(photoUrl!)
                                : null,
                            child: photoUrl == null
                                ? Icon(
                                    Icons.person_rounded,
                                    size: 55,
                                    color: Colors.white.withOpacity(0.9),
                                  )
                                : null,
                          ),
                        ),
                        if (isEditing)
                          Positioned(
                            bottom: 5,
                            right: 5,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.camera_alt_rounded,
                                size: 18,
                                color: Colors.blue.shade600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _nameController.text.isNotEmpty
                        ? _nameController.text
                        : 'Kullanıcı',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _emailController.text,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (isEditing) ...[
              _buildEditField(
                  'Ad Soyad', _nameController, Icons.person_rounded),
              _buildEditField('E-posta', _emailController, Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress),
              _buildEditField('Telefon', _phoneController, Icons.phone_rounded,
                  keyboardType: TextInputType.phone),
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    TextField(
                      controller: _addressController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Adres',
                        prefixIcon: Icon(Icons.location_on_rounded,
                            color: Colors.blue.shade600),
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
                          borderSide:
                              BorderSide(color: Colors.blue.shade600, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
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
                            Icons.info_outline_rounded,
                            size: 18,
                            color: Colors.blue.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Eğer ev adresinizden binmiyorsanız, bindiğiniz yerin adresini seçin',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _selectLocationFromMap,
                        icon:
                            const Icon(Icons.map_rounded, color: Colors.white),
                        label: const Text(
                          'Haritadan Seç',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelEdit,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade400),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'İptal',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'Kaydet',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              _buildInfoCard(
                  'Ad Soyad', _nameController.text, Icons.person_rounded),
              _buildInfoCard(
                  'E-posta', _emailController.text, Icons.email_rounded),
              _buildInfoCard(
                  'Telefon', _phoneController.text, Icons.phone_rounded),
              _buildInfoCard(
                  'Adres', _addressController.text, Icons.location_on_rounded),
              _buildInfoCard('Bölge', _getCleanRegionName(regionName),
                  Icons.location_city_rounded),
              _buildInfoCard('Şoför', driverName, Icons.drive_eta_rounded),
              _buildInfoCard(
                  'Araç Plakası',
                  _getCleanVehiclePlate(vehiclePlate),
                  Icons.directions_car_rounded),
              Container(
                margin: const EdgeInsets.only(bottom: 16),
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
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.science_rounded,
                          color: Colors.orange),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Test Modu',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Servis simülasyonlarını görmek için etkinleştirin',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _testModeEnabled,
                      onChanged: (v) async {
                        if (!mounted) return;
                        setState(() => _testModeEnabled = v);
                        await CacheService.setCache('passenger_test_mode', v);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(v
                                ? 'Test modu etkinleştirildi'
                                : 'Test modu kapatıldı'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.shade200,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded, color: Colors.white),
                  label: const Text(
                    'Çıkış Yap',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade500,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _selectLocationFromMap() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MapSelectionScreen(),
      ),
    );
    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _addressController.text = result['address'];
      });
      if (UserSession.userId != null) {
        print('🗺️ Harita seçiminden durak oluşturuluyor...');
        print('📍 Konum: ${result['latitude']}, ${result['longitude']}');
        print('📋 Adres: ${result['address']}');
        print('👤 Kullanıcı ID: ${UserSession.userId}');
        print('🏢 Bölge ID: ${UserSession.regionId}');
        print('🚗 Şoför ID: ${UserSession.driverId}');
        final stopId =
            await EnhancedStopManagementService.createStopFromMapSelection(
          latitude: result['latitude'],
          longitude: result['longitude'],
          address: result['address'],
          passengerId: UserSession.userId!,
        );
        final String selectedAddress = (result['address'] as String?)
                    ?.trim()
                    .isNotEmpty ==
                true
            ? (result['address'] as String)
            : '${(result['latitude'] as num).toDouble().toStringAsFixed(6)}, ${(result['longitude'] as num).toDouble().toStringAsFixed(6)}';
        try {
          await Future.wait([
            FirebaseFirestore.instance
                .collection('users')
                .doc(UserSession.userId!)
                .update({
              'address': selectedAddress,
              'lastUpdated': FieldValue.serverTimestamp(),
            }),
            FirebaseFirestore.instance
                .collection('passengers')
                .doc(UserSession.userId!)
                .set({
              'address': selectedAddress,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true)),
          ]);
        } catch (e) {
          print('⚠️ Adres kalıcılaştırma hatası: $e');
        }
        if (mounted) {
          if (stopId != null) {
            print('✅ Durak başarıyla oluşturuldu: $stopId');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('Durağınız başarıyla oluşturuldu!\nDurak ID: $stopId'),
                backgroundColor: Colors.green.shade600,
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'Tamam',
                  textColor: Colors.white,
                  onPressed: () {},
                ),
              ),
            );
          } else {
            print('❌ Durak oluşturulamadı!');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    'Durak oluşturulurken hata oluştu!\nKonsol loglarını kontrol edin.'),
                backgroundColor: Colors.red.shade600,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final String? uid =
          UserSession.userId ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Kullanıcı oturumu bulunamadı!'),
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
        return;
      }
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (image == null) return;
      if (mounted) setState(() => isLoading = true);
      final String ext = image.name.split('.').last.toLowerCase();
      final String fileName =
          'profile_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final Reference ref =
          FirebaseStorage.instance.ref().child('users/$uid/$fileName');
      UploadTask uploadTask;
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        uploadTask = ref.putData(
          bytes,
          SettableMetadata(contentType: 'image/$ext'),
        );
      } else {
        final file = File(image.path);
        uploadTask = ref.putFile(
          file,
          SettableMetadata(contentType: 'image/$ext'),
        );
      }
      final TaskSnapshot snap = await uploadTask.whenComplete(() {});
      final String downloadUrl = await snap.ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'photoUrl': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance
          .collection('passengers')
          .doc(uid)
          .set({'profileImageUrl': downloadUrl}, SetOptions(merge: true));
      UserSession.photoUrl = downloadUrl;
      try {
        final stops = await FirebaseFirestore.instance
            .collection('enhanced_stops')
            .where('passengerIds', arrayContains: uid)
            .where('isActive', isEqualTo: true)
            .get();
        for (final d in stops.docs) {
          await d.reference.update({
            'profileImageUrl': downloadUrl,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
        AvatarMarkerService.clearCache();
      } catch (_) {}
      if (mounted) {
        setState(() {
          photoUrl = downloadUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profil fotoğrafı güncellendi'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf yüklenemedi: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();
    if (name.isEmpty || email.isEmpty || phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ad, e-posta ve telefon alanları zorunludur!'),
            backgroundColor: Colors.blue.shade600,
          ),
        );
      }
      return;
    }
    if (UserSession.userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Kullanıcı oturumu bulunamadı!'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
      return;
    }
    if (mounted) {
      setState(() => isLoading = true);
    }
    try {
      final oldUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(UserSession.userId!)
          .get();
      final oldAddress =
          oldUserDoc.exists ? (oldUserDoc.data()?['address'] as String?) : null;
      final updateData = {
        'name': name,
        'email': email,
        'phone': phone,
        'address': address,
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      await Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .doc(UserSession.userId!)
            .update(updateData),
        FirebaseFirestore.instance
            .collection('passengers')
            .doc(UserSession.userId!)
            .update({
          'name': name,
          'email': email,
          'phone': phone,
          'address': address,
        }),
      ]);
      if (address.isNotEmpty &&
          address != oldAddress &&
          UserSession.regionId != null) {
        if (oldAddress != null && oldAddress.isNotEmpty) {
          await Future.wait([
            SimpleStopService.removePassengerFromStop(
              UserSession.userId!,
              UserSession.regionId!,
            ),
            EnhancedStopManagementService.removePassengerFromMapStop(
              UserSession.userId!,
            ),
          ]);
        }

        try {
          print('🔄 Yeni adres için otomatik durak işlemi başlatılıyor...');
          await SimpleStopService.createStopFromAddress(
            passengerId: UserSession.userId!,
            passengerName: name,
            address: address,
            regionId: UserSession.regionId!,
          );
          print('✅ Otomatik durak işlemi tamamlandı');
        } catch (e) {
          print('⚠️ Otomatik durak işlemi hatası: $e');
        }

        print('✅ Adres güncellendi, otomatik durak işlemi tamamlandı');
      }
      if (mounted) {
        setState(() => isEditing = false);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profil başarıyla güncellendi!'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _cancelEdit() {
    if (mounted) {
      setState(() => isEditing = false);
      _loadProfile();
    }
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      await UserSession.clear();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );
      }
    } catch (e) {
      print('Çıkış yapılırken hata: $e');
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (route) => false,
        );
      }
    }
  }

  Widget _buildInfoCard(String title, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
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
          color: Colors.grey.shade100,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.blue.shade400,
                  Colors.blue.shade500,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade200,
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isNotEmpty ? value : 'Belirtilmemiş',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditField(
      String label, TextEditingController controller, IconData icon,
      {TextInputType? keyboardType}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(icon, color: Colors.blue.shade600),
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
            borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class MapSelectionScreen extends StatefulWidget {
  const MapSelectionScreen({super.key});
  @override
  State<MapSelectionScreen> createState() => _MapSelectionScreenState();
}

class _MapSelectionScreenState extends State<MapSelectionScreen> {
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  String _selectedAddress = '';
  bool _isLoading = false;
  LatLng _initialPosition = const LatLng(41.0082, 28.9784);
  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _initialPosition = LatLng(position.latitude, position.longitude);
      });
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_initialPosition, 15),
        );
      }
    } catch (e) {
      print('Konum alma hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Konum Seç',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Color(0xFF4338CA),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_selectedLocation != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context, {
                  'latitude': _selectedLocation!.latitude,
                  'longitude': _selectedLocation!.longitude,
                  'address': _selectedAddress,
                });
              },
              child: const Text(
                'Seç',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              Future.delayed(const Duration(milliseconds: 500), () {
                if (_mapController != null) {
                  _mapController!.animateCamera(
                    CameraUpdate.newLatLngZoom(_initialPosition, 15),
                  );
                }
              });
            },
            initialCameraPosition: CameraPosition(
              target: _initialPosition,
              zoom: 10,
            ),
            onTap: _onMapTap,
            markers: _selectedLocation != null
                ? {
                    Marker(
                      markerId: const MarkerId('selected'),
                      position: _selectedLocation!,
                      infoWindow: InfoWindow(
                        title: 'Seçilen Konum',
                        snippet: _selectedAddress,
                      ),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueViolet),
                    ),
                  }
                : {},
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4338CA)),
                ),
              ),
            ),
          if (_selectedAddress.isNotEmpty)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFE0E7FF),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seçilen Adres:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4338CA),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedAddress,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onMapTap(LatLng location) async {
    setState(() {
      _selectedLocation = location;
      _isLoading = true;
    });
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final address = [
          placemark.street,
          placemark.subLocality,
          placemark.locality,
          placemark.administrativeArea,
        ].where((element) => element != null && element.isNotEmpty).join(', ');
        setState(() {
          _selectedAddress = address.isNotEmpty ? address : 'Adres bulunamadı';
        });
      } else {
        final alt = await GeocodingService.getAddressFromCoordinates(
          location.latitude,
          location.longitude,
        );
        setState(() {
          _selectedAddress = alt ??
              '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
        });
      }
    } catch (e) {
      try {
        final alt = await GeocodingService.getAddressFromCoordinates(
          location.latitude,
          location.longitude,
        );
        setState(() {
          _selectedAddress = alt ??
              '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
        });
      } catch (_) {
        setState(() {
          _selectedAddress =
              '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}';
        });
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

// Updated

