import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../widget/snackbar.dart';
import '../../utils/app_colors.dart';
import '../../providers/theme_provider.dart';

class DriverManagementScreen extends StatefulWidget {
  const DriverManagementScreen({super.key});
  @override
  State<DriverManagementScreen> createState() => _DriverManagementScreenState();
}

class _DriverManagementScreenState extends State<DriverManagementScreen> {
  String? _selectedRegionId;
  String? _selectedRegionName;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Şoför Yönetimi'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            try {
              print('[DriverManagement] Back button pressed');
              Navigator.of(context).pop();
              print('[DriverManagement] Navigation pop completed');
            } catch (e) {
              print('[DriverManagement] Back navigation error: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Geri gitme hatası: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
        actions: [],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('regions')
                  .orderBy('name')
                  .snapshots(),
              builder: (ctx, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Bölge seçin'),
                  value: _selectedRegionId,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Tüm Bölgeler'),
                    ),
                    ...snapshot.data!.docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return DropdownMenuItem(
                        value: doc.id,
                        child: Text(data['name'] ?? '—'),
                      );
                    }).toList(),
                  ],
                  onChanged: (val) {
                    if (val == null) {
                      setState(() {
                        _selectedRegionId = null;
                        _selectedRegionName = null;
                      });
                    } else {
                      final regionDoc = snapshot.data!.docs.firstWhere(
                        (d) => d.id == val,
                      );
                      final regionData =
                          regionDoc.data() as Map<String, dynamic>;
                      setState(() {
                        _selectedRegionId = val;
                        _selectedRegionName = regionData['name'];
                      });
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(child: DriversList(selectedRegionId: _selectedRegionId)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _showAddDriverDialog(context),
      ),
    );
  }

  void _showAddDriverDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final plateCtrl = TextEditingController();
    final _formKey = GlobalKey<FormState>();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Yeni Şoför Ekle'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ad Soyad',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ad Soyad alanı boş bırakılamaz';
                    }
                    if (value.trim().length < 2) {
                      return 'Ad Soyad en az 2 karakter olmalıdır';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'E-posta alanı boş bırakılamaz';
                    }
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                        .hasMatch(value.trim())) {
                      return 'Geçerli bir e-posta adresi giriniz';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Şifre',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Şifre alanı boş bırakılamaz';
                    }
                    if (value.trim().length < 6) {
                      return 'Şifre en az 6 karakter olmalıdır';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: plateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Plaka',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Plaka alanı boş bırakılamaz';
                    }
                    if (value.trim().length < 2) {
                      return 'Plaka en az 2 karakter olmalıdır';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _selectedRegionName == null
                        ? Colors.red.shade50
                        : Colors.green.shade50,
                    border: Border.all(
                      color: _selectedRegionName == null
                          ? Colors.red
                          : Colors.green,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _selectedRegionName == null
                            ? Icons.warning
                            : Icons.check_circle,
                        color: _selectedRegionName == null
                            ? Colors.red
                            : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedRegionName == null
                              ? 'Lütfen üstten bir bölge seçin'
                              : 'Seçilen Bölge: $_selectedRegionName',
                          style: TextStyle(
                            color: _selectedRegionName == null
                                ? Colors.red.shade700
                                : Colors.green.shade700,
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!_formKey.currentState!.validate()) {
                showSnackBar(
                  text: 'Lütfen tüm alanları doğru şekilde doldurun.',
                  backgroundColor: Colors.red.shade700,
                );
                return;
              }
              if (_selectedRegionId == null) {
                showSnackBar(
                  text: 'Lütfen bir bölge seçin.',
                  backgroundColor: Colors.red.shade700,
                );
                return;
              }
              final name = nameCtrl.text.trim();
              final email = emailCtrl.text.trim();
              final password = passCtrl.text.trim();
              final plate = plateCtrl.text.trim();
              final regionId = _selectedRegionId!;
              if (name.isEmpty ||
                  email.isEmpty ||
                  password.isEmpty ||
                  plate.isEmpty) {
                showSnackBar(
                  text: 'Tüm alanlar doldurulmalıdır.',
                  backgroundColor: Colors.red.shade700,
                );
                return;
              }
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(
                  child: CircularProgressIndicator(),
                ),
              );
              try {
                final result = await addDriver(
                  name,
                  email,
                  password,
                  regionId,
                  plate,
                );
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
                if (result) {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                  showSnackBar(
                    text: 'Şoför başarıyla eklendi!',
                    backgroundColor: Colors.green.shade700,
                    duration: const Duration(seconds: 2),
                  );
                  nameCtrl.clear();
                  emailCtrl.clear();
                  passCtrl.clear();
                  plateCtrl.clear();
                  setState(() {
                    _selectedRegionId = null;
                    _selectedRegionName = null;
                  });
                } else {
                  showSnackBar(
                    text:
                        'Şoför eklenirken hata oluştu. Lütfen tekrar deneyin.',
                    backgroundColor: Colors.red.shade700,
                  );
                }
              } catch (e) {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
                showSnackBar(
                  text: 'Beklenmeyen bir hata oluştu: $e',
                  backgroundColor: Colors.red.shade700,
                );
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  Future<bool> addDriver(
    String name,
    String email,
    String password,
    String regionId,
    String vehiclePlate,
  ) async {
    try {
      if (name.trim().isEmpty ||
          email.trim().isEmpty ||
          password.trim().isEmpty ||
          regionId.trim().isEmpty ||
          vehiclePlate.trim().isEmpty) {
        print('[DriverManagement] Boş parametre tespit edildi');
        return false;
      }
      print('[DriverManagement] Şoför ekleme işlemi başlatılıyor...');
      print('[DriverManagement] Email: $email');
      print('[DriverManagement] Name: $name');
      print('[DriverManagement] Region: $regionId');
      print('[DriverManagement] Plate: $vehiclePlate');
      final existingUsers = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email.trim())
          .get();
      if (existingUsers.docs.isNotEmpty) {
        print('[DriverManagement] Bu email ile zaten bir kullanıcı mevcut');
        showSnackBar(
          text: 'Bu e-posta adresi ile zaten bir kullanıcı mevcut.',
          backgroundColor: Colors.red.shade700,
        );
        return false;
      }
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        showSnackBar(
          text: 'Oturum hatası. Lütfen tekrar giriş yapın.',
          backgroundColor: Colors.red.shade700,
        );
        return false;
      }
      final adminEmail = currentUser.email;
      final adminUid = currentUser.uid;
      try {
        final uc = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password.trim(),
        );
        final newDriverUid = uc.user!.uid;
        print(
            '[DriverManagement] Yeni şoför hesabı oluşturuldu: $newDriverUid');
        await uc.user!.sendEmailVerification();
        print('[DriverManagement] Email doğrulama gönderildi');
        await FirebaseFirestore.instance
            .collection('users')
            .doc(newDriverUid)
            .set({
          'name': name.trim(),
          'email': email.trim(),
          'role': 'Şoför',
          'regionId': regionId.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'emailVerified': false,
          'isActive': true,
        });
        print('[DriverManagement] Users koleksiyonuna eklendi');
        await FirebaseFirestore.instance
            .collection('drivers')
            .doc(newDriverUid)
            .set({
          'name': name.trim(),
          'email': email.trim(),
          'vehiclePlate': vehiclePlate.trim().toUpperCase(),
          'regionId': regionId.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'active',
          'isActive': true,
          'dutyStatus': 'off_duty',
        });
        print('[DriverManagement] Drivers koleksiyonuna eklendi');
        await FirebaseAuth.instance.signOut();
        print('[DriverManagement] Yeni şoför hesabından çıkış yapıldı');
        try {
          print(
              '[DriverManagement] Admin kullanıcısı auth state güncelleniyor...');
        } catch (reAuthError) {
          print('[DriverManagement] Admin re-auth hatası: $reAuthError');
        }
        print('[DriverManagement] Şoför başarıyla eklendi');
        return true;
      } catch (authError) {
        print('[DriverManagement] Auth hatası: $authError');
        throw authError;
      }
    } catch (e) {
      print('[DriverManagement] Şoför ekleme hatası: $e');
      String errorMessage = 'Şoför eklenirken hata oluştu.';
      if (e.toString().contains('email-already-in-use')) {
        errorMessage = 'Bu e-posta adresi zaten kullanımda.';
      } else if (e.toString().contains('weak-password')) {
        errorMessage = 'Şifre çok zayıf. Daha güçlü bir şifre seçin.';
      } else if (e.toString().contains('invalid-email')) {
        errorMessage = 'Geçersiz e-posta adresi.';
      } else if (e.toString().contains('network')) {
        errorMessage = 'İnternet bağlantısı sorunu. Lütfen tekrar deneyin.';
      }
      showSnackBar(
        text: errorMessage,
        backgroundColor: Colors.red.shade700,
      );
      return false;
    }
  }
}

class DriversList extends StatelessWidget {
  final String? selectedRegionId;
  const DriversList({super.key, this.selectedRegionId});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: selectedRegionId == null
          ? FirebaseFirestore.instance
              .collection('drivers')
              .orderBy('createdAt', descending: true)
              .snapshots()
          : FirebaseFirestore.instance
              .collection('drivers')
              .where('regionId', isEqualTo: selectedRegionId)
              .orderBy('createdAt', descending: true)
              .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final drivers = snapshot.data!.docs;
        if (drivers.isEmpty) {
          return Center(
            child: Text(
              selectedRegionId == null
                  ? "Şoför bulunamadı."
                  : "Bu bölgede şoför bulunamadı.",
              style: TextStyle(color: AppColors.textDark),
            ),
          );
        }
        return FutureBuilder<Map<String, String>>(
          future: _getRegionNames(),
          builder: (context, regionSnapshot) {
            final regionNames = regionSnapshot.data ?? {};
            return ListView.builder(
              itemCount: drivers.length,
              itemBuilder: (ctx, i) {
                final driver = drivers[i].data() as Map<String, dynamic>;
                final regionName = regionNames[driver['regionId']] ??
                    driver['regionId'] ??
                    '—';
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(driver['name'] ?? '—'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("E-posta: ${driver['email'] ?? '—'}"),
                        Text("Plaka: ${driver['vehiclePlate'] ?? '—'}"),
                        Text("Bölge: $regionName"),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<Map<String, String>> _getRegionNames() async {
    final regionsSnapshot =
        await FirebaseFirestore.instance.collection('regions').get();
    final Map<String, String> regionNames = {};
    for (final doc in regionsSnapshot.docs) {
      final data = doc.data();
      regionNames[doc.id] = data['name'] ?? '—';
    }
    return regionNames;
  }
}



 Again


