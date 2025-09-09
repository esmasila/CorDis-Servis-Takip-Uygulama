import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widget/snackbar.dart';
import '../../utils/app_colors.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({Key? key}) : super(key: key);
  @override
  _EmployeeManagementScreenState createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _selectedRegionId;
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

  Future<String> getRegionName(String regionId) async {
    final doc = await FirebaseFirestore.instance
        .collection('regions')
        .doc(regionId)
        .get();
    final data = doc.data();
    return data?['name'] ?? regionId;
  }

  Future<String> _getDriverName(String? driverId) async {
    if (driverId == null || driverId.isEmpty) {
      return 'Atanmamış';
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(driverId)
          .get();
      if (doc.exists) {
        final data = doc.data();
        return data?['name'] ?? 'Bilinmeyen Şoför';
      } else {
        return 'Şoför Bulunamadı';
      }
    } catch (e) {
      return 'Hata';
    }
  }

  Future<void> _showDriverAssignmentDialog(
      String passengerId, Map<String, dynamic> passengerData) async {
    String? selectedDriverId = passengerData['driverId'];
    String passengerRegionId = passengerData['regionId'] ?? '';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Şoför Atama - ${passengerData['name'] ?? 'Yolcu'}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Bölge: ${passengerData['regionId'] ?? 'Bilinmeyen'}'),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('drivers')
                      .where('regionId', isEqualTo: passengerRegionId)
                      .where('status', isEqualTo: 'active')
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
                        labelText: 'Şoför Seçin',
                        border: OutlineInputBorder(),
                      ),
                      value: selectedDriverId,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Şoför Atanmamış'),
                        ),
                        ...activeDrivers.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text(
                                '${data['name']} - ${data['vehiclePlate']}'),
                          );
                        }).toList(),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          selectedDriverId = value;
                        });
                      },
                    );
                  },
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
              onPressed: () async {
                await _assignDriverToPassenger(passengerId, selectedDriverId);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Ata'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assignDriverToPassenger(
      String passengerId, String? driverId) async {
    try {
      await FirebaseFirestore.instance
          .collection('passengers')
          .doc(passengerId)
          .update({
        'driverId': driverId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      showSnackBar(
        text: driverId != null
            ? 'Şoför başarıyla atandı!'
            : 'Şoför ataması kaldırıldı!',
        backgroundColor: Colors.green.shade700,
      );
    } catch (e) {
      showSnackBar(
        text: 'Şoför atama işlemi başarısız: $e',
        backgroundColor: Colors.red.shade700,
      );
    }
  }

  Widget _buildRegionFilter() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('regions')
          .orderBy('name')
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          showSnackBar(
            text: 'Bölgeler yüklenirken hata: ${snap.error}',
            backgroundColor: Colors.red.shade700,
          );
          return const SizedBox.shrink();
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Bölge Filtre'),
            value: _selectedRegionId,
            isExpanded: true,
            items: snap.data!.docs.map((doc) {
              final data = doc.data()! as Map<String, dynamic>;
              return DropdownMenuItem(
                value: doc.id,
                child: Text(data['name'] ?? '—'),
              );
            }).toList(),
            onChanged: (v) => setState(() => _selectedRegionId = v),
          ),
        );
      },
    );
  }

  Widget _buildList(String role) {
    final collection = role == 'Şoför' ? 'drivers' : 'users';
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection(
      collection,
    );
    if (role == 'Şoför') {
      query = query.where('status', isEqualTo: 'active');
    } else {
      query = query.where('role', isEqualTo: 'Yolcu');
    }
    if (_selectedRegionId != null) {
      query = query.where('regionId', isEqualTo: _selectedRegionId);
    }
    query = role == 'Şoför'
        ? query.orderBy('createdAt', descending: true)
        : query.orderBy('name');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          showSnackBar(
            text: '$role listelenirken hata: ${snap.error}',
            backgroundColor: Colors.red.shade700,
          );
          return Center(child: Text('Hata: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(child: Text('$role kaydı bulunamadı.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (ctx, i) {
            final data = docs[i].data();
            final title = data['name'] ?? data['email'] ?? '—';
            final subtitle = role == 'Şoför'
                ? 'Plaka: ${data['vehiclePlate'] ?? '-'}'
                : 'E-posta: ${data['email'] ?? '-'}';
            final regionId = data['regionId'] ?? '';
            return ListTile(
              title: Text(title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subtitle),
                  if (role == 'Yolcu' && data.containsKey('stopId'))
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collectionGroup('stops')
                          .where(
                            FieldPath.documentId,
                            isEqualTo: data['stopId'],
                          )
                          .limit(1)
                          .get()
                          .then((snap) => snap.docs.first),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Text("Durak yükleniyor...");
                        }
                        final stopData =
                            snapshot.data!.data() as Map<String, dynamic>;
                        return Text("Durak: ${stopData['name'] ?? '-'}");
                      },
                    ),
                  if (role == 'Yolcu')
                    FutureBuilder<String>(
                      future: _getDriverName(data['driverId']),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Text("Şoför yükleniyor...");
                        }
                        return Text(
                          "Şoför: ${snapshot.data!}",
                          style: TextStyle(
                            color: snapshot.data == 'Atanmamış'
                                ? Colors.red
                                : Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
                    ),
                ],
              ),
              trailing: role == 'Yolcu'
                  ? IconButton(
                      icon: const Icon(Icons.assignment_ind),
                      onPressed: () =>
                          _showDriverAssignmentDialog(docs[i].id, data),
                      tooltip: 'Şoför Ata',
                    )
                  : FutureBuilder<String>(
                      future: getRegionName(regionId),
                      builder: (_, snapshot) {
                        if (!snapshot.hasData) {
                          return const SizedBox(
                            width: 40,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        }
                        return Text(
                          snapshot.data!,
                          style: const TextStyle(fontSize: 12),
                        );
                      },
                    ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Kullanıcı Yönetimi'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Şoförler'),
            Tab(text: 'Yolcular'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildRegionFilter(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildList('Şoför'), _buildList('Yolcu')],
            ),
          ),
        ],
      ),
    );
  }
}

// Updated


// Updated Again

