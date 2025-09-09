import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../service/stop_tracking_service.dart';
import '../service/user_session.dart';
class StopTrackingWidget extends StatefulWidget {
  final String driverId;
  const StopTrackingWidget({
    Key? key,
    required this.driverId,
  }) : super(key: key);
  @override
  State<StopTrackingWidget> createState() => _StopTrackingWidgetState();
}
class _StopTrackingWidgetState extends State<StopTrackingWidget> {
  List<Map<String, dynamic>> _todayVisits = [];
  Map<String, dynamic>? _currentStopVisit;
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadTodayVisits();
    _listenToCurrentStopVisit();
  }
  Future<void> _loadTodayVisits() async {
    try {
      final visits = await StopTrackingService.getDailyStopReport(
        driverId: widget.driverId,
      );
      if (mounted) {
        setState(() {
          _todayVisits = visits;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Günlük ziyaret yükleme hatası: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  void _listenToCurrentStopVisit() {
    FirebaseFirestore.instance
        .collection('stop_visits')
        .where('driverId', isEqualTo: widget.driverId)
        .where('status', isEqualTo: 'arrived')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _currentStopVisit =
              snapshot.docs.isNotEmpty ? snapshot.docs.first.data() : null;
        });
      }
    });
  }
  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes}dk ${remainingSeconds}sn';
  }
  String _formatTime(DateTime time) {
    return DateFormat('HH:mm').format(time);
  }
  Color _getStatusColor(String status) {
    switch (status) {
      case 'arrived':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
  Widget _buildCurrentStopCard() {
    if (_currentStopVisit == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Şu anda hiçbir durakta değilsiniz',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final stopName = _currentStopVisit!['stopName'] ?? 'Bilinmeyen Durak';
    final arrivalTime =
        (_currentStopVisit!['arrivalTime'] as Timestamp).toDate();
    final waitDuration = DateTime.now().difference(arrivalTime).inSeconds;
    final isEarlyArrival = _currentStopVisit!['isEarlyArrival'] ?? false;
    final earlyMinutes = _currentStopVisit!['earlyMinutes'];
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  color: Colors.orange,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Şu anda: $stopName',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Varış: ${_formatTime(arrivalTime)}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            Text(
              'Bekleme süresi: ${_formatDuration(waitDuration)}',
              style: const TextStyle(fontSize: 16),
            ),
            if (isEarlyArrival && earlyMinutes != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Erken varış: ${earlyMinutes} dakika',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontSize: 12,
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
  Widget _buildTodayVisitsList() {
    if (_todayVisits.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Bugün henüz durak ziyareti yok',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Bugünkü Durak Ziyaretleri',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _todayVisits.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final visit = _todayVisits[index];
              final stopName = visit['stopName'] ?? 'Bilinmeyen Durak';
              final arrivalTime = visit['arrivalTime'] as DateTime;
              final departureTime = visit['departureTime'] as DateTime?;
              final waitDuration = visit['waitDuration'] as int?;
              final passengerCount = visit['passengerCount'] as int? ?? 0;
              final status = visit['status'] ?? 'unknown';
              final isEarlyArrival = visit['isEarlyArrival'] ?? false;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getStatusColor(status),
                  child: Icon(
                    status == 'completed' ? Icons.check : Icons.access_time,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: Text(
                  stopName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Varış: ${_formatTime(arrivalTime)}'),
                    if (departureTime != null)
                      Text('Ayrılış: ${_formatTime(departureTime)}'),
                    if (waitDuration != null)
                      Text('Bekleme: ${_formatDuration(waitDuration)}'),
                    if (passengerCount > 0) Text('Yolcu: $passengerCount kişi'),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isEarlyArrival)
                      Icon(
                        Icons.schedule,
                        color: Colors.blue,
                        size: 16,
                      ),
                    Text(
                      status == 'completed' ? 'Tamamlandı' : 'Devam ediyor',
                      style: TextStyle(
                        color: _getStatusColor(status),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
  Widget _buildStatisticsCard() {
    final completedVisits =
        _todayVisits.where((v) => v['status'] == 'completed').toList();
    final totalWaitTime = completedVisits
        .where((v) => v['waitDuration'] != null)
        .map((v) => v['waitDuration'] as int)
        .fold(0, (sum, duration) => sum + duration);
    final avgWaitTime =
        completedVisits.isNotEmpty ? totalWaitTime / completedVisits.length : 0;
    final totalPassengers = completedVisits
        .map((v) => v['passengerCount'] as int? ?? 0)
        .fold(0, (sum, count) => sum + count);
    final earlyArrivals =
        _todayVisits.where((v) => v['isEarlyArrival'] == true).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Günlük İstatistikler',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Toplam Durak',
                    '${_todayVisits.length}',
                    Icons.location_on,
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Tamamlanan',
                    '${completedVisits.length}',
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Ort. Bekleme',
                    avgWaitTime > 0
                        ? _formatDuration(avgWaitTime.round())
                        : '0dk',
                    Icons.access_time,
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Toplam Yolcu',
                    '$totalPassengers',
                    Icons.people,
                    Color(0xFF6366F1),
                  ),
                ),
              ],
            ),
            if (earlyArrivals > 0) ...[
              const SizedBox(height: 12),
              _buildStatItem(
                'Erken Varış',
                '$earlyArrivals',
                Icons.schedule,
                Colors.blue,
              ),
            ]
          ],
        ),
      ),
    );
  }
  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildCurrentStopCard(),
          const SizedBox(height: 16),
          _buildStatisticsCard(),
          const SizedBox(height: 16),
          _buildTodayVisitsList(),
        ],
      ),
    );
  }
}

// Updated

