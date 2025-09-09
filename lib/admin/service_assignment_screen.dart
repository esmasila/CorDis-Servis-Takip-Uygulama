import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceAssignmentScreen extends StatefulWidget {
  const ServiceAssignmentScreen({Key? key}) : super(key: key);
  @override
  _ServiceAssignmentScreenState createState() =>
      _ServiceAssignmentScreenState();
}

class _ServiceAssignmentScreenState extends State<ServiceAssignmentScreen> {
  final _regions = FirebaseFirestore.instance.collection('regions');
  final _drivers = FirebaseFirestore.instance.collection('drivers');
  final _services = FirebaseFirestore.instance.collection('services');
  final _stops = FirebaseFirestore.instance.collection('enhanced_stops');
  String? _selectedRegionId;
  String? _selectedDriverId;
  String? _selectedServiceId;
  bool _showStopSequence = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final regionsSnapshot = await _regions.orderBy('name').get();
      if (regionsSnapshot.docs.isNotEmpty) {
        setState(() {
          _selectedRegionId = regionsSnapshot.docs.first.id;
        });
      }
    } catch (e) {
      print('Başlangıç verisi yükleme hatası: $e');
      if (mounted) {
        _showSnackBarUltimate(
          'Veri yükleme hatası: $e',
          backgroundColor: Colors.red.shade700,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor ?? Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSnackBarSafe(String message, {Color? backgroundColor}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final messenger = ScaffoldMessenger.of(context);
          if (messenger.mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: backgroundColor ?? Colors.green.shade700,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          print('SnackBar gösterme hatası: $e');
        }
      }
    });
  }

  void _showSnackBarGlobal(String message, {Color? backgroundColor}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final messenger = ScaffoldMessenger.of(context);
          if (messenger.mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: backgroundColor ?? Colors.green.shade700,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          print('SnackBar gösterme hatası: $e');
        }
      }
    });
  }

  void _showSnackBarFinal(String message, {Color? backgroundColor}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final messenger = ScaffoldMessenger.of(context);
          if (messenger.mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: backgroundColor ?? Colors.green.shade700,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          print('SnackBar gösterme hatası: $e');
        }
      }
    });
  }

  void _showSnackBarPerfect(String message, {Color? backgroundColor}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final messenger = ScaffoldMessenger.of(context);
          if (messenger.mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: backgroundColor ?? Colors.green.shade700,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          print('SnackBar gösterme hatası: $e');
        }
      }
    });
  }

  void _showSnackBarUltimate(String message, {Color? backgroundColor}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final messenger = ScaffoldMessenger.of(context);
          if (messenger.mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: backgroundColor ?? Colors.green.shade700,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          print('SnackBar gösterme hatası: $e');
        }
      }
    });
  }

  Future<String> getRegionName(String regionId) async {
    try {
      final doc = await _regions.doc(regionId).get();
      if (!doc.exists) return 'Bilinmeyen Bölge';
      final data = doc.data();
      return data?['name'] ?? regionId;
    } catch (e) {
      print('Bölge adı getirme hatası: $e');
      return 'Hata: $e';
    }
  }

  Future<String> getDriverName(String driverId) async {
    try {
      final doc = await _drivers.doc(driverId).get();
      if (!doc.exists) {
        return 'Silinmiş Sürücü';
      }
      final data = doc.data();
      if (data == null ||
          data['isActive'] != true ||
          data['status'] != 'active') {
        return 'Pasif Sürücü';
      }
      return data['name'] ?? driverId;
    } catch (e) {
      print('Sürücü adı getirme hatası: $e');
      return 'Hata: $e';
    }
  }

  Future<List<Map<String, dynamic>>> getStopsForRegion(String regionId) async {
    try {
      final querySnapshot = await _stops
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: false)
          .get();

      final activeStops = <Map<String, dynamic>>[];

      for (final doc in querySnapshot.docs) {
        final data = doc.data();

        if (data['isActive'] == true &&
            data['isDeleted'] != true &&
            data['deletedAt'] == null &&
            data['status'] != 'deleted' &&
            data['status'] != 'inactive' &&
            data['deleted'] != true &&
            data['isArchived'] != true &&
            data['archived'] != true &&
            data['isMainRoad'] != true) {
          data['id'] = doc.id;
          activeStops.add(data);
        } else {
          print(
              '❌ Durak filtrelendi: ${data['name']} - isActive: ${data['isActive']}, isDeleted: ${data['isDeleted']}, deletedAt: ${data['deletedAt']}, status: ${data['status']}, isMainRoad: ${data['isMainRoad']}');
        }
      }

      print(
          '📊 Bölge $regionId için toplam ${activeStops.length} aktif durak bulundu');
      return activeStops;
    } catch (e) {
      print('Durak getirme hatası: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getActiveServices() async {
    try {
      final driverSnapshot = await _drivers
          .where('status', isEqualTo: 'active')
          .where('isActive', isEqualTo: true)
          .get();

      final activeDriverIds = driverSnapshot.docs.map((doc) => doc.id).toList();

      if (activeDriverIds.isEmpty) {
        return <Map<String, dynamic>>[];
      }

      Query query = _services.where('driverId', whereIn: activeDriverIds);

      if (_selectedRegionId != null) {
        query = query.where('regionId', isEqualTo: _selectedRegionId);
      }

      final serviceSnapshot =
          await query.orderBy('startTime', descending: true).get();

      final activeServices = <Map<String, dynamic>>[];
      for (final doc in serviceSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final driverId = data['driverId'] as String?;

        if (driverId != null && activeDriverIds.contains(driverId)) {
          data['id'] = doc.id;
          activeServices.add(data);
        }
      }

      return activeServices;
    } catch (e) {
      print('Aktif servisleri getirme hatası: $e');
      return [];
    }
  }

  Future<void> _cleanupDeletedDriverServices() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final activeDrivers = await _drivers
          .where('status', isEqualTo: 'active')
          .where('isActive', isEqualTo: true)
          .get();

      final activeDriverIds = activeDrivers.docs.map((doc) => doc.id).toSet();

      if (activeDriverIds.isEmpty) {
        return;
      }

      final allServices = await _services.get();

      int deletedCount = 0;
      for (final serviceDoc in allServices.docs) {
        final serviceData = serviceDoc.data() as Map<String, dynamic>;
        final driverId = serviceData['driverId'] as String?;

        if (driverId != null && !activeDriverIds.contains(driverId)) {
          await serviceDoc.reference.delete();
          deletedCount++;
        }
      }

      print('Toplam $deletedCount servis temizlendi.');
    } catch (e) {
      print('Servis temizleme hatası: $e');
      if (mounted) {
        _showSnackBarUltimate(
          'Temizleme hatası: $e',
          backgroundColor: Colors.red.shade700,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Servis Takip'),
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.cleaning_services),
              tooltip: 'Silinen Sürücü Servislerini Temizle',
              onPressed: _isLoading
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Servis Temizleme'),
                          content: const Text(
                              'Silinen sürücülere ait tüm servisler temizlenecek. Bu işlem geri alınamaz. Devam etmek istiyor musunuz?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('İptal'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Temizle'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        await _cleanupDeletedDriverServices();
                        setState(() {});
                      }
                    },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Servis Atama'),
              Tab(text: 'Durak Sırası'),
            ],
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              try {
                Navigator.of(context).pop();
              } catch (e) {
                if (mounted) {
                  _showSnackBarUltimate(
                    'Geri gitme hatası: $e',
                    backgroundColor: Colors.red.shade700,
                  );
                }
              }
            },
          ),
        ),
        body: TabBarView(
          children: [
            _buildServiceAssignmentTab(),
            _buildStopSequenceTab(),
          ],
        ),
        floatingActionButton: _selectedRegionId == null
            ? null
            : FloatingActionButton.extended(
                icon: const Icon(Icons.schedule),
                label: const Text('Planla'),
                onPressed: _showPlanServiceDialog,
              ),
      ),
    );
  }

  Widget _buildServiceAssignmentTab() {
    return Column(
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: _regions.orderBy('name').snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snap.data!.docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Text('Henüz bölge tanımlanmamış'),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(8),
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Bölge Seçin',
                  border: OutlineInputBorder(),
                ),
                value: _selectedRegionId,
                items: snap.data!.docs.map((d) {
                  final r = d.data()! as Map<String, dynamic>;
                  return DropdownMenuItem(
                    value: d.id,
                    child: Text(r['name'] ?? ''),
                  );
                }).toList(),
                onChanged: (v) => setState(() {
                  _selectedRegionId = v;
                  _selectedDriverId = null;
                }),
                isExpanded: true,
              ),
            );
          },
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _getActiveServices(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 64, color: Colors.red.shade300),
                      const SizedBox(height: 16),
                      Text('Hata: ${snap.error}'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => setState(() {}),
                        child: const Text('Tekrar Dene'),
                      ),
                    ],
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final services = snap.data!;
              if (services.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.schedule, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Henüz servis planlanmadı.'),
                      SizedBox(height: 8),
                      Text(
                        'Yeni servis planlamak için "Planla" butonunu kullanın.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: services.length,
                itemBuilder: (ctx, index) {
                  final data = services[index];
                  final start = (data['startTime'] as Timestamp?)?.toDate();
                  final startStr = start != null
                      ? '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/${start.year} ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}'
                      : '-';
                  final regionId = data['regionId'] ?? '';
                  final driverId = data['driverId'] ?? '';

                  return FutureBuilder<List<String>>(
                    future: Future.wait([
                      getRegionName(regionId),
                      getDriverName(driverId),
                    ]),
                    builder: (_, snapshot) {
                      if (!snapshot.hasData) {
                        return const Card(
                          margin:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: ListTile(
                            title: Text("Yükleniyor..."),
                            leading: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final regionName = snapshot.data![0];
                      final driverName = snapshot.data![1];

                      Color driverColor = Colors.black;
                      if (driverName.contains('Silinmiş') ||
                          driverName.contains('Pasif')) {
                        driverColor = Colors.red;
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: ListTile(
                          title: Text(
                            'Bölge: $regionName | Şoför: $driverName',
                            style: TextStyle(
                              color: driverName.contains('Silinmiş') ||
                                      driverName.contains('Pasif')
                                  ? Colors.red
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            'Başlangıç: $startStr\nDurum: ${data['status'] ?? 'Bilinmiyor'}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.route),
                            onPressed: () =>
                                _showStopSequenceForService(data['id']),
                            tooltip: 'Durak Sırasını Göster',
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStopSequenceTab() {
    if (_selectedRegionId == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_on, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Lütfen önce bir bölge seçin',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Durak sırasını görmek için bölge seçimi yapın',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info, color: Colors.blue.shade700, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Durak Sırası',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Seçilen bölgedeki durakların sırası ve aktif şoförler',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: getStopsForRegion(_selectedRegionId!),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Hata: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final stops = snapshot.data!;
              if (stops.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_off, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Bu bölgede henüz durak bulunmuyor',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: const Text(
                      'Aktif Şoförler',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 120,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _drivers
                          .where('regionId', isEqualTo: _selectedRegionId)
                          .where('status', isEqualTo: 'active')
                          .where('isActive', isEqualTo: true)
                          .snapshots(),
                      builder: (context, driverSnapshot) {
                        if (!driverSnapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        final drivers = driverSnapshot.data!.docs;
                        if (drivers.isEmpty) {
                          return const Center(
                            child: Text('Bu bölgede aktif şoför bulunmuyor'),
                          );
                        }

                        return ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: drivers.length,
                          itemBuilder: (context, index) {
                            final driver =
                                drivers[index].data() as Map<String, dynamic>;
                            return Container(
                              width: 200,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.drive_eta,
                                              color: Colors.green),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              driver['name'] ?? 'İsimsiz',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Plaka: ${driver['vehiclePlate'] ?? '—'}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      Text(
                                        'Durum: ${driver['dutyStatus'] ?? 'off_duty'}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: const Text(
                      'Durak Sırası',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: stops.length,
                      itemBuilder: (context, index) {
                        final stop = stops[index];
                        final stopNumber = index + 1;

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Center(
                                child: Text(
                                  stopNumber.toString(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              stop['name'] ?? 'İsimsiz Durak',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Adres: ${stop['address'] ?? 'Belirtilmemiş'}',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                                Text(
                                  'Yolcu Sayısı: ${(stop['passengerIds'] as List?)?.length ?? 0}',
                                ),
                                if (stop['isMainRoad'] == true)
                                  Text(
                                    'Ana Yol Durağı',
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _showStopSequenceForService(String serviceId) {
    setState(() {
      _selectedServiceId = serviceId;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Servis Durak Sırası'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _services.doc(serviceId).get().then((doc) => doc.data()!),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final service = snapshot.data!;
              final regionId = service['regionId'];

              return FutureBuilder<List<Map<String, dynamic>>>(
                future: getStopsForRegion(regionId),
                builder: (context, stopsSnapshot) {
                  if (!stopsSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final stops = stopsSnapshot.data!;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bölge: ${service['regionId']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          itemCount: stops.length,
                          itemBuilder: (context, index) {
                            final stop = stops[index];
                            final stopNumber = index + 1;

                            return ListTile(
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: Text(
                                    stopNumber.toString(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                stop['name'] ?? 'İsimsiz Durak',
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                stop['address'] ?? 'Adres belirtilmemiş',
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
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

  void _showPlanServiceDialog() {
    if (_selectedRegionId == null) {
      _showSnackBarUltimate(
        'Lütfen önce bir bölge seçin',
        backgroundColor: Colors.red.shade700,
      );
      return;
    }

    _selectedDriverId = null;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Yeni Servis Planla'),
        content: StatefulBuilder(
          builder: (ctx, setState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: _drivers
                      .where('status', isEqualTo: 'active')
                      .where('isActive', isEqualTo: true)
                      .where('regionId', isEqualTo: _selectedRegionId)
                      .orderBy('name')
                      .snapshots(),
                  builder: (_, snapshot) {
                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final activeDrivers = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['isActive'] == true &&
                          data['status'] == 'active';
                    }).toList();

                    if (activeDrivers.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.person_off,
                                  size: 48, color: Colors.grey),
                              SizedBox(height: 8),
                              Text(
                                'Bu bölgede aktif sürücü bulunamadı.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 14),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Önce sürücü ekleyin veya mevcut sürücüleri aktif hale getirin.',
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return DropdownButtonFormField<String>(
                      value: _selectedDriverId,
                      decoration: const InputDecoration(
                        labelText: 'Şoför',
                        border: OutlineInputBorder(),
                      ),
                      items: activeDrivers.map((d) {
                        final dr = d.data()! as Map<String, dynamic>;
                        return DropdownMenuItem(
                          value: d.id,
                          child: Text(dr['name'] ?? 'İsimsiz Sürücü'),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setState(() => _selectedDriverId = val),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Lütfen şoför seçin';
                        }
                        return null;
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
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_selectedDriverId == null) {
                if (mounted) {
                  _showSnackBarUltimate(
                    'Lütfen şoför seçin',
                    backgroundColor: Colors.red.shade700,
                  );
                }
                return;
              }

              try {
                setState(() {
                  _isLoading = true;
                });

                await _services.add({
                  'regionId': _selectedRegionId,
                  'driverId': _selectedDriverId,
                  'startTime': DateTime.now(),
                  'status': 'planlanmış',
                  'createdAt': DateTime.now(),
                  'updatedAt': DateTime.now(),
                });

                if (mounted) {
                  _showSnackBarUltimate(
                    'Servis başarıyla planlandı!',
                    backgroundColor: Colors.green.shade700,
                  );
                  Navigator.of(dialogCtx).pop();
                }

                if (mounted) {
                  setState(() {});
                }
              } catch (e) {
                print('Servis planlama hatası: $e');
                if (mounted) {
                  _showSnackBarUltimate(
                    'Planlama hatası: $e',
                    backgroundColor: Colors.red.shade700,
                  );
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });
                }
              }
            },
            child: const Text('Planla'),
          ),
        ],
      ),
    );
  }
}

// Updated


// Updated Again

