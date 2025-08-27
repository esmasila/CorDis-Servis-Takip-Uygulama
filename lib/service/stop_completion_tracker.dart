import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class StopCompletionTracker {
  static final StopCompletionTracker _instance =
      StopCompletionTracker._internal();
  factory StopCompletionTracker() => _instance;
  StopCompletionTracker._internal();

  // Tamamlanan durakları takip eden set
  final Set<String> _completedStops = <String>{};

  // Stream subscription'ları
  StreamSubscription<QuerySnapshot>? _stopLogsSubscription;

  // Callback fonksiyonu - marker'ları yeniden çizmek için
  VoidCallback? _onStopsUpdated;

  /// Durak tamamlama durumunu takip etmeye başla
  void startTracking({
    required String driverId,
    required VoidCallback onStopsUpdated,
  }) {
    _onStopsUpdated = onStopsUpdated;
    _trackStopLogs(driverId);
  }

  /// Durak tamamlama durumunu takip etmeyi durdur
  void stopTracking() {
    _stopLogsSubscription?.cancel();
    _completedStops.clear();
    _onStopsUpdated = null;
  }

  /// Belirli bir durağın tamamlanıp tamamlanmadığını kontrol et
  bool isStopCompleted(String stopId) {
    return _completedStops.contains(stopId);
  }

  /// Tamamlanan durakların listesini al
  Set<String> get completedStops => Set.from(_completedStops);

  /// Durak loglarını takip et
  void _trackStopLogs(String driverId) {
    _stopLogsSubscription?.cancel();

    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    print(
        '🔍 StopCompletionTracker: Durak logları takip ediliyor - Driver: $driverId');
    print('   - Tarih aralığı: $startOfDay -> $endOfDay');

    _stopLogsSubscription = FirebaseFirestore.instance
        .collection('stop_logs')
        .where('driverId', isEqualTo: driverId)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
        .snapshots()
        .listen((snapshot) {
      print(
          '📡 StopCompletionTracker: ${snapshot.docs.length} log dokümanı alındı');

      final completed = <String>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        final stopId = data['stopId'] as String?;
        final type = data['type'] as String?;
        final timestamp = data['timestamp'] as Timestamp?;

        print(
            '   - Log: $stopId -> Status: $status, Type: $type, Timestamp: $timestamp');

        // Completion loglarını ve status loglarını kabul et
        if (stopId != null &&
            (status == 'completed' ||
                status == 'arrived' ||
                status == 'visited' ||
                type == 'completion')) {
          completed.add(stopId);
          print('   ✅ Durak tamamlandı: $stopId');
        }
      }

      // Tamamlanan durakları güncelle
      print('📊 StopCompletionTracker: Tamamlanan duraklar: $completed');

      if (_completedStops != completed) {
        _completedStops.clear();
        _completedStops.addAll(completed);
        print('✅ StopCompletionTracker: Durak durumu güncellendi');
        print('   - Toplam tamamlanan: ${_completedStops.length}');

        // Marker'ları yeniden çizmek için callback'i çağır
        _onStopsUpdated?.call();

        if (kDebugMode) {
          print(
              '🔄 Durak tamamlama durumu güncellendi: ${_completedStops.length} durak tamamlandı');
        }
      }
    }, onError: (error) {
      print('❌ StopCompletionTracker: Durak log takip hatası: $error');
    });
  }

  /// Manuel olarak bir durağı tamamlandı olarak işaretle
  void markStopAsCompleted(String stopId) {
    if (!_completedStops.contains(stopId)) {
      _completedStops.add(stopId);
      _onStopsUpdated?.call();

      if (kDebugMode) {
        print('✅ Durak manuel olarak tamamlandı: $stopId');
      }
    }
  }

  /// Manuel olarak bir durağı tamamlanmamış olarak işaretle
  void markStopAsIncomplete(String stopId) {
    if (_completedStops.contains(stopId)) {
      _completedStops.remove(stopId);
      _onStopsUpdated?.call();

      if (kDebugMode) {
        print(
            '❌ Durak manuel olarak tamamlanmamış olarak işaretlendi: $stopId');
      }
    }
  }

  /// Tüm durakları sıfırla
  void resetAllStops() {
    _completedStops.clear();
    _onStopsUpdated?.call();

    if (kDebugMode) {
      print('🔄 Tüm durak durumları sıfırlandı');
    }
  }
}
