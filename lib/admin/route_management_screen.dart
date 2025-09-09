import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widget/snackbar.dart';
import 'firestore_service.dart';
import '../service/auto_route_service.dart';

class RouteManagementScreen extends StatefulWidget {
  const RouteManagementScreen({super.key});
  @override
  State<RouteManagementScreen> createState() => _RouteManagementScreenState();
}

class _RouteManagementScreenState extends State<RouteManagementScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedRegionId;
  String? _selectedDriverId;
  late TabController _tabController;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rota Yönetimi'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            try {
              print('[RouteManagement] Back button pressed');
              Navigator.of(context).pop();
              print('[RouteManagement] Navigation pop completed');
            } catch (e) {
              print('[RouteManagement] Back navigation error: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Geri gitme hatası: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(
              icon: Icon(Icons.route),
              text: 'Rota Yönetimi',
            ),
            Tab(
              icon: Icon(Icons.history),
              text: 'Rota Logları',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRouteManagementTab(),
          _buildRouteLogsTab(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: _generateTodayRoutes,
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Bugün'),
            heroTag: 'today_routes',
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            onPressed: _generateTomorrowRoutes,
            backgroundColor: Colors.orange.shade700,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Yarın'),
            heroTag: 'tomorrow_routes',
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            onPressed: () => _showAddRouteDialog(),
            backgroundColor: Colors.blue.shade700,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add),
            heroTag: 'manual_route',
          ),
        ],
      ),
    );
  }

  Stream<QuerySnapshot> _buildRoutesStream() {
    Query query = FirebaseFirestore.instance.collection('routes');
    if (_selectedRegionId != null) {
      query = query.where('regionId', isEqualTo: _selectedRegionId);
    }
    if (_selectedDriverId != null) {
      query = query.where('driverId', isEqualTo: _selectedDriverId);
    }
    return query.orderBy('createdAt', descending: true).snapshots();
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'Belirtilmemiş';
    try {
      final DateTime dateTime = (timestamp as Timestamp).toDate();
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Geçersiz zaman';
    }
  }

  void _showAddRouteDialog() {
    final routeNameController = TextEditingController();
    String? selectedDriverId;
    String? selectedRegionId = _selectedRegionId;
    List<Map<String, dynamic>> stops = [];
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Yeni Rota Ekle'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: routeNameController,
                    decoration: const InputDecoration(
                      labelText: 'Rota Adı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('regions')
                        .orderBy('name')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }
                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Bölge',
                          border: OutlineInputBorder(),
                        ),
                        value: selectedRegionId,
                        items: snapshot.data!.docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem(
                            value: doc.id,
                            child: Text(data['name'] ?? '—'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedRegionId = val;
                            selectedDriverId = null;
                          });
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (selectedRegionId != null)
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('drivers')
                          .where('regionId', isEqualTo: selectedRegionId)
                          .where('status', isEqualTo: 'active')
                          .where('isActive', isEqualTo: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const CircularProgressIndicator();
                        }

                        final activeDrivers = snapshot.data!.docs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final isActive = data['isActive'] == true;
                          final isNotDeleted = data['isDeleted'] != true;
                          final hasValidStatus = data['status'] == 'active';

                          final finalIsActive =
                              data['isActive'] == null ? true : isActive;
                          final finalIsNotDeleted =
                              data['isDeleted'] == null ? true : isNotDeleted;

                          return finalIsActive &&
                              finalIsNotDeleted &&
                              hasValidStatus;
                        }).toList();

                        if (activeDrivers.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Bu bölgede aktif sürücü bulunamadı',
                              style: TextStyle(color: Colors.grey),
                            ),
                          );
                        }

                        return DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Şoför',
                            border: OutlineInputBorder(),
                          ),
                          value: selectedDriverId,
                          items: activeDrivers.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return DropdownMenuItem(
                              value: doc.id,
                              child: Text(
                                  '${data['name']} - ${data['vehiclePlate']}'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedDriverId = val;
                            });
                          },
                        );
                      },
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          title: const Text('Başlangıç'),
                          subtitle: Text(startTime?.format(context) ?? 'Seçin'),
                          onTap: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (time != null) {
                              setDialogState(() {
                                startTime = time;
                              });
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          title: const Text('Bitiş'),
                          subtitle: Text(endTime?.format(context) ?? 'Seçin'),
                          onTap: () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                            );
                            if (time != null) {
                              setDialogState(() {
                                endTime = time;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Duraklar:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...stops
                      .map((stop) => ListTile(
                            title: Text(stop['name']),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                setDialogState(() {
                                  stops.remove(stop);
                                });
                              },
                            ),
                          ))
                      .toList(),
                  ElevatedButton(
                    onPressed: () => _addStopToRoute(setDialogState, stops),
                    child: const Text('Durak Ekle'),
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
                if (routeNameController.text.trim().isEmpty ||
                    selectedRegionId == null ||
                    selectedDriverId == null ||
                    startTime == null ||
                    endTime == null) {
                  showSnackBar(
                    text: 'Lütfen tüm alanları doldurun.',
                    backgroundColor: Colors.red.shade700,
                  );
                  return;
                }
                try {
                  final now = DateTime.now();
                  final startDateTime = DateTime(
                    now.year,
                    now.month,
                    now.day,
                    startTime!.hour,
                    startTime!.minute,
                  );
                  final endDateTime = DateTime(
                    now.year,
                    now.month,
                    now.day,
                    endTime!.hour,
                    endTime!.minute,
                  );
                  await AdminFirestoreService.createRoute(
                    driverId: selectedDriverId!,
                    regionId: selectedRegionId!,
                    routeName: routeNameController.text.trim(),
                    stops: stops,
                    startTime: startDateTime,
                    endTime: endDateTime,
                  );
                  showSnackBar(text: 'Rota başarıyla eklendi!');
                  Navigator.pop(context);
                } catch (e) {
                  showSnackBar(
                    text: 'Rota eklenirken hata oluştu: $e',
                    backgroundColor: Colors.red.shade700,
                  );
                }
              },
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
  }

  void _addStopToRoute(
      StateSetter setDialogState, List<Map<String, dynamic>> stops) {
    final stopNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Durak Ekle'),
        content: TextField(
          controller: stopNameController,
          decoration: const InputDecoration(
            labelText: 'Durak Adı',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (stopNameController.text.trim().isNotEmpty) {
                setDialogState(() {
                  stops.add({
                    'name': stopNameController.text.trim(),
                    'latitude': 0.0,
                    'longitude': 0.0,
                  });
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  void _editRoute(String routeId, Map<String, dynamic> route) {
    _showEditRouteDialog(routeId, route);
  }

  void _showEditRouteDialog(String routeId, Map<String, dynamic> route) {
    final routeNameController =
        TextEditingController(text: route['routeName'] ?? '');
    List<Map<String, dynamic>> stops =
        List<Map<String, dynamic>>.from(route['stops'] ?? []);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Rota Düzenle'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: routeNameController,
                    decoration: const InputDecoration(
                      labelText: 'Rota Adı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Duraklar:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...stops.asMap().entries.map((entry) {
                    final index = entry.key;
                    final stop = entry.value;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text('${index + 1}'),
                          backgroundColor: Colors.blue.shade100,
                        ),
                        title: Text(stop['name'] ?? 'İsimsiz Durak'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editStopInRoute(
                                  setDialogState, stops, index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setDialogState(() {
                                  stops.removeAt(index);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _addStopToEditRoute(setDialogState, stops),
                    icon: const Icon(Icons.add),
                    label: const Text('Yeni Durak Ekle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
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
                if (routeNameController.text.trim().isEmpty) {
                  showSnackBar(
                    text: 'Lütfen rota adını girin.',
                    backgroundColor: Colors.red.shade700,
                  );
                  return;
                }
                try {
                  await AdminFirestoreService.updateRoute(routeId, {
                    'routeName': routeNameController.text.trim(),
                    'stops': stops,
                  });
                  showSnackBar(text: 'Rota başarıyla güncellendi!');
                  Navigator.pop(context);
                } catch (e) {
                  showSnackBar(
                    text: 'Rota güncellenirken hata oluştu: $e',
                    backgroundColor: Colors.red.shade700,
                  );
                }
              },
              child: const Text('Güncelle'),
            ),
          ],
        ),
      ),
    );
  }

  void _editStopInRoute(
      StateSetter setDialogState, List<Map<String, dynamic>> stops, int index) {
    final stopNameController =
        TextEditingController(text: stops[index]['name'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Durak Düzenle'),
        content: TextField(
          controller: stopNameController,
          decoration: const InputDecoration(
            labelText: 'Durak Adı',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (stopNameController.text.trim().isNotEmpty) {
                setDialogState(() {
                  stops[index] = {
                    ...stops[index],
                    'name': stopNameController.text.trim(),
                  };
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Güncelle'),
          ),
        ],
      ),
    );
  }

  void _addStopToEditRoute(
      StateSetter setDialogState, List<Map<String, dynamic>> stops) {
    final stopNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni Durak Ekle'),
        content: TextField(
          controller: stopNameController,
          decoration: const InputDecoration(
            labelText: 'Durak Adı',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (stopNameController.text.trim().isNotEmpty) {
                setDialogState(() {
                  stops.add({
                    'name': stopNameController.text.trim(),
                    'latitude': 0.0,
                    'longitude': 0.0,
                  });
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  void _deleteRoute(String routeId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rota Sil'),
        content: const Text('Bu rotayı silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await AdminFirestoreService.deleteRoute(routeId);
                showSnackBar(text: 'Rota başarıyla silindi!');
                Navigator.pop(context);
              } catch (e) {
                showSnackBar(
                  text: 'Rota silinirken hata oluştu: $e',
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

  void _generateTodayRoutes() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Bugün için rotalar oluşturuluyor...'),
            ],
          ),
        ),
      );
      final today = DateTime.now();
      final driversSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('status', isEqualTo: 'active')
          .get();
      int successCount = 0;
      int errorCount = 0;
      for (final driverDoc in driversSnapshot.docs) {
        final driverData = driverDoc.data();
        final driverId = driverDoc.id;
        final regionId = driverData['regionId'];
        if (regionId != null) {
          try {
            final result = await AutoRouteService.generateAutoRoute(
              driverId: driverId,
              regionId: regionId,
              routeDate: today,
            );
            if (result == null) {
              successCount++;
            } else {
              errorCount++;
              print(
                  '[RouteManagement] Şoför $driverId için rota hatası: $result');
            }
          } catch (e) {
            errorCount++;
            print(
                '[RouteManagement] Şoför $driverId için rota oluşturma hatası: $e');
          }
        }
      }
      Navigator.pop(context);
      showSnackBar(
        text:
            'Bugün için rotalar oluşturuldu! Başarılı: $successCount, Hatalı: $errorCount',
        backgroundColor: errorCount > 0 ? Colors.orange : Colors.green,
      );
    } catch (e) {
      Navigator.pop(context);
      showSnackBar(
        text: 'Rota oluşturulurken hata: $e',
        backgroundColor: Colors.red.shade700,
      );
    }
  }

  void _generateTomorrowRoutes() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Yarın için rotalar oluşturuluyor...'),
            ],
          ),
        ),
      );
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final driversSnapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('status', isEqualTo: 'active')
          .get();
      int successCount = 0;
      int errorCount = 0;
      for (final driverDoc in driversSnapshot.docs) {
        final driverData = driverDoc.data();
        final driverId = driverDoc.id;
        final regionId = driverData['regionId'];
        if (regionId != null) {
          try {
            final result = await AutoRouteService.generateAutoRoute(
              driverId: driverId,
              regionId: regionId,
              routeDate: tomorrow,
            );
            if (result == null) {
              successCount++;
            } else {
              errorCount++;
              print(
                  '[RouteManagement] Şoför $driverId için rota hatası: $result');
            }
          } catch (e) {
            errorCount++;
            print(
                '[RouteManagement] Şoför $driverId için rota oluşturma hatası: $e');
          }
        }
      }
      Navigator.pop(context);
      showSnackBar(
        text:
            'Yarın için rotalar oluşturuldu! Başarılı: $successCount, Hatalı: $errorCount',
        backgroundColor: errorCount > 0 ? Colors.orange : Colors.green,
      );
    } catch (e) {
      Navigator.pop(context);
      showSnackBar(
        text: 'Rota oluşturulurken hata: $e',
        backgroundColor: Colors.red.shade700,
      );
    }
  }

  Widget _buildRouteManagementTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('regions')
                .orderBy('name')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Hata: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const CircularProgressIndicator();
              }
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Bölge Seçin',
                  border: OutlineInputBorder(),
                ),
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
                  setState(() {
                    _selectedRegionId = val;
                    _selectedDriverId = null;
                  });
                },
              );
            },
          ),
        ),
        if (_selectedRegionId != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('drivers')
                  .where('regionId', isEqualTo: _selectedRegionId)
                  .where('status', isEqualTo: 'active')
                  .where('isActive', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }

                final activeDrivers = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final isActive = data['isActive'] == true;
                  final isNotDeleted = data['isDeleted'] != true;
                  final hasValidStatus = data['status'] == 'active';

                  final finalIsActive =
                      data['isActive'] == null ? true : isActive;
                  final finalIsNotDeleted =
                      data['isDeleted'] == null ? true : isNotDeleted;

                  return finalIsActive && finalIsNotDeleted && hasValidStatus;
                }).toList();

                if (activeDrivers.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Bu bölgede aktif sürücü bulunamadı',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Şoför Seçin',
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedDriverId,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Tüm Şoförler'),
                    ),
                    ...activeDrivers.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return DropdownMenuItem(
                        value: doc.id,
                        child:
                            Text('${data['name']} - ${data['vehiclePlate']}'),
                      );
                    }).toList(),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedDriverId = val;
                    });
                  },
                );
              },
            ),
          ),
        const SizedBox(height: 10),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _buildRoutesStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Hata: ${snapshot.error}'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final routes = snapshot.data!.docs;
              if (routes.isEmpty) {
                return const Center(
                  child: Text(
                    'Henüz rota bulunmuyor.\nYeni rota eklemek için + butonuna tıklayın.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                );
              }
              return ListView.builder(
                itemCount: routes.length,
                itemBuilder: (context, index) {
                  final route = routes[index].data() as Map<String, dynamic>;
                  final routeId = routes[index].id;
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ExpansionTile(
                      leading: Icon(
                        Icons.route,
                        color: route['status'] == 'active'
                            ? Colors.green
                            : Colors.orange,
                      ),
                      title: Text(
                        route['routeName'] ?? 'İsimsiz Rota',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Durum: ${route['status'] ?? 'Bilinmeyen'}'),
                          if (route['startTime'] != null)
                            Text(
                                'Başlangıç: ${_formatTime(route['startTime'])}'),
                          if (route['endTime'] != null)
                            Text('Bitiş: ${_formatTime(route['endTime'])}'),
                          Text(
                              'Durak Sayısı: ${(route['stops'] as List?)?.length ?? 0}'),
                          if (route['updatedAt'] != null)
                            Text(
                                'Son Güncelleme: ${_formatTime(route['updatedAt'])}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Duraklar:',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        _addQuickStopToRoute(routeId),
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Hızlı Ekle'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade600,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (route['stops'] != null &&
                                  (route['stops'] as List).isNotEmpty)
                                ...List.generate(
                                  (route['stops'] as List).length,
                                  (stopIndex) {
                                    final stop = route['stops'][stopIndex];
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 4),
                                      child: ListTile(
                                        dense: true,
                                        leading: CircleAvatar(
                                          radius: 12,
                                          child: Text('${stopIndex + 1}'),
                                          backgroundColor: Colors.blue.shade100,
                                        ),
                                        title: Text(
                                            stop['name'] ?? 'İsimsiz Durak'),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.remove_circle,
                                              color: Colors.red, size: 20),
                                          onPressed: () => _removeStopFromRoute(
                                              routeId, stopIndex),
                                        ),
                                      ),
                                    );
                                  },
                                )
                              else
                                const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Text('Henüz durak eklenmemiş.',
                                      style: TextStyle(
                                          fontStyle: FontStyle.italic)),
                                ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () => _editRoute(routeId, route),
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: const Text('Düzenle'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _deleteRoute(routeId),
                                    icon: const Icon(Icons.delete, size: 16),
                                    label: const Text('Sil'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRouteLogsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('regions')
                      .orderBy('name')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }
                    return DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Bölge',
                        border: OutlineInputBorder(),
                      ),
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
                        setState(() {
                          _selectedRegionId = val;
                          _selectedDriverId = null;
                        });
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              if (_selectedRegionId != null)
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('drivers')
                        .where('regionId', isEqualTo: _selectedRegionId)
                        .where('status', isEqualTo: 'active')
                        .where('isActive', isEqualTo: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }

                      final activeDrivers = snapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final isActive = data['isActive'] == true;
                        final isNotDeleted = data['isDeleted'] != true;
                        final hasValidStatus = data['status'] == 'active';

                        final finalIsActive =
                            data['isActive'] == null ? true : isActive;
                        final finalIsNotDeleted =
                            data['isDeleted'] == null ? true : isNotDeleted;

                        return finalIsActive &&
                            finalIsNotDeleted &&
                            hasValidStatus;
                      }).toList();

                      if (activeDrivers.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Bu bölgede aktif sürücü bulunamadı',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Şoför',
                          border: OutlineInputBorder(),
                        ),
                        value: _selectedDriverId,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Tüm Şoförler'),
                          ),
                          ...activeDrivers.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return DropdownMenuItem(
                              value: doc.id,
                              child: Text(data['name'] ?? '—'),
                            );
                          }).toList(),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedDriverId = val;
                          });
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _buildRouteLogsStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Hata: ${snapshot.error}'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final logs = snapshot.data!.docs;
              if (logs.isEmpty) {
                return const Center(
                  child: Text(
                    'Henüz rota logu bulunmuyor.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                );
              }
              return ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final log = logs[index].data() as Map<String, dynamic>;
                  final logId = logs[index].id;
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ExpansionTile(
                      leading: Icon(
                        Icons.history,
                        color: log['status'] == 'completed'
                            ? Colors.green
                            : log['status'] == 'in_progress'
                                ? Colors.orange
                                : Colors.grey,
                      ),
                      title: Text(
                        log['routeName'] ?? 'İsimsiz Rota',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Şoför: ${log['driverName'] ?? 'Bilinmeyen'}'),
                          Text('Durum: ${_getStatusText(log['status'])}'),
                          if (log['startTime'] != null)
                            Text(
                                'Başlangıç: ${_formatDateTime(log['startTime'])}'),
                          if (log['endTime'] != null)
                            Text('Bitiş: ${_formatDateTime(log['endTime'])}'),
                        ],
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Durak Logları:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              if (log['stopLogs'] != null)
                                ...List.generate(
                                  (log['stopLogs'] as List).length,
                                  (stopIndex) {
                                    final stopLog = log['stopLogs'][stopIndex];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: stopLog['visited'] == true
                                            ? Colors.green.shade50
                                            : Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: stopLog['visited'] == true
                                              ? Colors.green.shade200
                                              : Colors.grey.shade200,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            stopLog['visited'] == true
                                                ? Icons.check_circle
                                                : Icons.radio_button_unchecked,
                                            color: stopLog['visited'] == true
                                                ? Colors.green
                                                : Colors.grey,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  stopLog['stopName'] ??
                                                      'İsimsiz Durak',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (stopLog['visitTime'] !=
                                                    null)
                                                  Text(
                                                    'Ziyaret: ${_formatDateTime(stopLog['visitTime'])}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                                if (stopLog['passengerCount'] !=
                                                    null)
                                                  Text(
                                                    'Yolcu Sayısı: ${stopLog['passengerCount']}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color:
                                                          Colors.grey.shade600,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              const SizedBox(height: 16),
                              if (log['totalDistance'] != null)
                                _buildLogInfoItem(
                                  'Toplam Mesafe',
                                  '${(log['totalDistance'] / 1000).toStringAsFixed(1)} km',
                                  Icons.straighten,
                                ),
                              if (log['totalDuration'] != null)
                                _buildLogInfoItem(
                                  'Toplam Süre',
                                  '${(log['totalDuration'] / 60).toStringAsFixed(0)} dakika',
                                  Icons.access_time,
                                ),
                              if (log['completedStops'] != null &&
                                  log['totalStops'] != null)
                                _buildLogInfoItem(
                                  'Tamamlanan Duraklar',
                                  '${log['completedStops']}/${log['totalStops']}',
                                  Icons.location_on,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLogInfoItem(String title, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue.shade600, size: 20),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: Colors.blue.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Stream<QuerySnapshot> _buildRouteLogsStream() {
    Query query = FirebaseFirestore.instance
        .collection('route_logs')
        .orderBy('startTime', descending: true);
    if (_selectedRegionId != null) {
      query = query.where('regionId', isEqualTo: _selectedRegionId);
    }
    if (_selectedDriverId != null) {
      query = query.where('driverId', isEqualTo: _selectedDriverId);
    }
    return query.limit(50).snapshots();
  }

  String _formatDateTime(dynamic timestamp) {
    if (timestamp == null) return 'Belirtilmemiş';
    try {
      final DateTime dateTime = (timestamp as Timestamp).toDate();
      return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Geçersiz tarih';
    }
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'completed':
        return 'Tamamlandı';
      case 'in_progress':
        return 'Devam Ediyor';
      case 'cancelled':
        return 'İptal Edildi';
      default:
        return 'Bilinmeyen';
    }
  }

  void _addQuickStopToRoute(String routeId) {
    showDialog(
      context: context,
      builder: (context) {
        String stopName = '';
        double? latitude;
        double? longitude;
        return AlertDialog(
          title: const Text('Hızlı Durak Ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Durak Adı',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => stopName = value,
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Enlem (Latitude)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  latitude = double.tryParse(value);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Boylam (Longitude)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  longitude = double.tryParse(value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (stopName.isNotEmpty &&
                    latitude != null &&
                    longitude != null) {
                  try {
                    final newStop = {
                      'name': stopName,
                      'latitude': latitude,
                      'longitude': longitude,
                      'addedAt': FieldValue.serverTimestamp(),
                    };
                    await AdminFirestoreService.addStopToRoute(
                        routeId, newStop);
                    if (mounted) {
                      Navigator.pop(context);
                      showSnackBar(
                        text: 'Durak başarıyla eklendi!',
                        backgroundColor: Colors.green.shade700,
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      showSnackBar(
                        text: 'Durak eklenirken hata oluştu: $e',
                        backgroundColor: Colors.red.shade700,
                      );
                    }
                  }
                } else {
                  showSnackBar(
                    text: 'Lütfen tüm alanları doldurun!',
                    backgroundColor: Colors.red.shade700,
                  );
                }
              },
              child: const Text('Ekle'),
            ),
          ],
        );
      },
    );
  }

  void _removeStopFromRoute(String routeId, int stopIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Durak Sil'),
        content:
            const Text('Bu durağı rotadan silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await AdminFirestoreService.removeStopFromRoute(
                    routeId, stopIndex);
                if (mounted) {
                  Navigator.pop(context);
                  showSnackBar(
                    text: 'Durak başarıyla silindi!',
                    backgroundColor: Colors.green.shade700,
                  );
                }
              } catch (e) {
                if (mounted) {
                  showSnackBar(
                    text: 'Durak silinirken hata oluştu: $e',
                    backgroundColor: Colors.red.shade700,
                  );
                }
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


