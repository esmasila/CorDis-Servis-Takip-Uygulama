import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  await Firebase.initializeApp();

  print('🔍 Enhanced_stops koleksiyonundaki koordinatları kontrol ediliyor...');

  try {
    final stopsSnapshot =
        await FirebaseFirestore.instance.collection('enhanced_stops').get();

    print('📊 Toplam durak sayısı: ${stopsSnapshot.docs.length}');
    print('\n--- KOORDİNAT KONTROLÜ ---');

    int zeroCoordinateCount = 0;
    int validCoordinateCount = 0;

    for (var doc in stopsSnapshot.docs) {
      final data = doc.data();
      final name = data['name'] as String?;
      final latitude = data['latitude'] as double?;
      final longitude = data['longitude'] as double?;
      final address = data['address'] as String?;
      final isActive = data['isActive'] as bool?;

      print('Durak: $name');
      print('  - ID: ${doc.id}');
      print('  - Adres: $address');
      print('  - Latitude: $latitude');
      print('  - Longitude: $longitude');
      print('  - Aktif: $isActive');

      if (latitude == null ||
          longitude == null ||
          latitude == 0.0 ||
          longitude == 0.0) {
        print('  ❌ SORUNLU KOORDİNAT!');
        zeroCoordinateCount++;
      } else {
        print('  ✅ Geçerli koordinat');
        validCoordinateCount++;
      }
      print('---');
    }

    print('\n📈 SONUÇ:');
    print('✅ Geçerli koordinatlı durak sayısı: $validCoordinateCount');
    print('❌ Sorunlu koordinatlı durak sayısı: $zeroCoordinateCount');

    if (zeroCoordinateCount > 0) {
      print('\n🔧 Koordinat sorunu tespit edildi!');
      print('Bu durakların koordinatları düzeltilmeli.');
    } else {
      print('\n✅ Tüm durakların koordinatları geçerli.');
    }

    print('\n✅ Kontrol tamamlandı!');
  } catch (e) {
    print('❌ Hata oluştu: $e');
  }
}
