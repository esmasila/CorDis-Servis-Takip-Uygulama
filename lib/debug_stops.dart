import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
void main() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('🔍 Enhanced_stops koleksiyonundaki durakları kontrol ediliyor...');
  try {
    final stopsSnapshot =
        await FirebaseFirestore.instance.collection('enhanced_stops').get();
    print('📊 Toplam durak sayısı: ${stopsSnapshot.docs.length}');
    print('\n--- DURAK LİSTESİ ---');
    Map<String, int> regionCounts = {};
    for (var doc in stopsSnapshot.docs) {
      final data = doc.data();
      final regionId = data['regionId'] as String?;
      final name = data['name'] as String?;
      final isActive = data['isActive'] as bool?;
      final source = data['source'] as String?;
      print('Durak ID: ${doc.id}');
      print('  - İsim: $name');
      print('  - RegionId: $regionId');
      print('  - Aktif: $isActive');
      print('  - Kaynak: $source');
      print('  - Oluşturma: ${data['createdAt']}');
      print('---');
      if (regionId != null) {
        regionCounts[regionId] = (regionCounts[regionId] ?? 0) + 1;
      }
    }
    print('\n📈 BÖLGE BAŞINA DURAK SAYILARI:');
    regionCounts.forEach((regionId, count) {
      print('RegionId: $regionId -> $count durak');
    });
    print('\n🔍 Regions koleksiyonundaki bölgeleri kontrol ediliyor...');
    final regionsSnapshot =
        await FirebaseFirestore.instance.collection('regions').get();
    print('📊 Toplam bölge sayısı: ${regionsSnapshot.docs.length}');
    print('\n--- BÖLGE LİSTESİ ---');
    for (var doc in regionsSnapshot.docs) {
      final data = doc.data();
      final name = data['name'] as String?;
      final stopCount = regionCounts[doc.id] ?? 0;
      print('Bölge ID: ${doc.id}');
      print('  - İsim: $name');
      print('  - Bu bölgedeki durak sayısı: $stopCount');
      print('---');
    }
    print('\n✅ Debug tamamlandı!');
  } catch (e) {
    print('❌ Hata oluştu: $e');
  }
}

// Updated


// Updated Again

