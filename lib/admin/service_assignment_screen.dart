import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widget/snackbar.dart';
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
  String? _selectedRegionId;
  String? _selectedDriverId;
  Future<String> getRegionName(String regionId) async {
    final doc = await _regions.doc(regionId).get();
    final data = doc.data();
    return data?['name'] ?? regionId;
  }
  Future<String> getDriverName(String driverId) async {
    final doc = await _drivers.doc(driverId).get();
    final data = doc.data();
    return data?['name'] ?? driverId;
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Servis Atama'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            try {
              print('[ServiceAssignment] Back button pressed');
              Navigator.of(context).pop();
              print('[ServiceAssignment] Navigation pop completed');
            } catch (e) {
              print('[ServiceAssignment] Back navigation error: $e');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Geri gitme hatası: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
      ),
      body: Column(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: _regions.orderBy('name').snapshots(),
            builder: (_, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.all(8),
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Bölge Seçin'),
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
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  (_selectedRegionId != null
                          ? _services.where(
                              'regionId',
                              isEqualTo: _selectedRegionId,
                            )
                          : _services)
                      .orderBy('startTime', descending: true)
                      .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  showSnackBar(
                    text: 'Servisler yüklenirken hata: ${snap.error}',
                    backgroundColor: Colors.red.shade700,
                  );
                  return Center(child: Text('Hata: ${snap.error}'));
                }
                if (!snap.hasData)
                  return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty)
                  return const Center(child: Text('Henüz servis planlanmadı.'));
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (ctx, index) {
                    final data = docs[index].data()! as Map<String, dynamic>;
                    final start = (data['startTime'] as Timestamp?)?.toDate();
                    final startStr = start != null
                        ? '${start.day}/${start.month}/${start.year} ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}'
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
                          return const ListTile(title: Text("Yükleniyor..."));
                        }
                        final regionName = snapshot.data![0];
                        final driverName = snapshot.data![1];
                        return ListTile(
                          title: Text(
                            'Bölge: $regionName | Şoför: $driverName',
                          ),
                          subtitle: Text(
                            'Başlangıç: $startStr\nDurum: ${data['status']}',
                          ),
                          isThreeLine: true,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedRegionId == null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.schedule),
              label: const Text('Planla'),
              onPressed: _showPlanServiceDialog,
            ),
    );
  }
  void _showPlanServiceDialog() {
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
                      .where('regionId', isEqualTo: _selectedRegionId)
                      .snapshots(),
                  builder: (_, snapshot) {
                    if (!snapshot.hasData)
                      return const CircularProgressIndicator();
                    return DropdownButtonFormField<String>(
                      value: _selectedDriverId,
                      decoration: const InputDecoration(labelText: 'Şoför'),
                      items: snapshot.data!.docs.map((d) {
                        final dr = d.data()! as Map<String, dynamic>;
                        return DropdownMenuItem(
                          value: d.id,
                          child: Text(dr['name'] ?? ''),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setState(() => _selectedDriverId = val),
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
                showSnackBar(
                  text: 'Lütfen şoför seçin',
                  backgroundColor: Colors.red.shade700,
                );
                return;
              }
              try {
                await _services.add({
                  'regionId': _selectedRegionId,
                  'driverId': _selectedDriverId,
                  'startTime': DateTime.now(),
                  'status': 'planlanmış',
                });
                showSnackBar(text: 'Servis planlandı.');
                Navigator.of(dialogCtx).pop();
              } catch (e) {
                showSnackBar(
                  text: 'Planlama hatası: $e',
                  backgroundColor: Colors.red.shade700,
                );
              }
            },
            child: const Text('Planla'),
          ),
        ],
      ),
    );
  }
}
