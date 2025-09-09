import 'package:cloud_firestore/cloud_firestore.dart';
import '../service/geocoding_service.dart';
class CoordinateFixer {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Future<void> fixAllStopCoordinates() async {
    try {
      print('🔍 Tüm durakların koordinatları kontrol ediliyor...');
      final stopsSnapshot = await _firestore
          .collection('enhanced_stops')
          .where('isActive', isEqualTo: true)
          .get();
      int totalStops = stopsSnapshot.docs.length;
      int fixedCount = 0;
      int validCount = 0;
      int errorCount = 0;
      print('📊 Toplam durak sayısı: $totalStops');
      for (final doc in stopsSnapshot.docs) {
        try {
          final data = doc.data();
          final latitude = data['latitude'] as double?;
          final longitude = data['longitude'] as double?;
          final address = data['address'] as String?;
          final stopName = data['name'] as String? ?? 'İsimsiz Durak';
          print('\n🔍 Kontrol ediliyor: $stopName');
          print('   Adres: $address');
          print('   Mevcut koordinatlar: ($latitude, $longitude)');
          if (latitude == null || longitude == null || 
              latitude == 0.0 || longitude == 0.0 ||
              latitude.abs() > 90 || longitude.abs() > 180) {
            print('   ❌ Geçersiz koordinatlar tespit edildi');
            if (address != null && address.trim().isNotEmpty) {
              print('   🔄 Adres koordinatlara çevriliyor...');
              final coordinates = await GeocodingService.getCoordinatesFromAddress(address);
              if (coordinates != null) {
                await doc.reference.update({
                  'latitude': coordinates['latitude'],
                  'longitude': coordinates['longitude'],
                  'lastUpdated': FieldValue.serverTimestamp(),
                  'coordinatesFixed': true,
                  'coordinatesValidated': true,
                });
                fixedCount++;
                print('   ✅ Koordinatlar düzeltildi: (${coordinates['latitude']}, ${coordinates['longitude']})');
              } else {
                errorCount++;
                print('   ❌ Koordinat alınamadı');
              }
            } else {
              errorCount++;
              print('   ❌ Adres bilgisi eksik');
            }
          } else {
            validCount++;
            print('   ✅ Koordinatlar geçerli');
          }
        } catch (e) {
          errorCount++;
          print('   ❌ Durak işleme hatası: $e');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
      print('\n🎉 Koordinat düzeltme işlemi tamamlandı!');
      print('📊 ÖZET:');
      print('   Toplam durak: $totalStops');
      print('   Geçerli koordinat: $validCount');
      print('   Düzeltilen koordinat: $fixedCount');
      print('   Hata: $errorCount');
    } catch (e) {
      print('❌ Koordinat düzeltme genel hatası: $e');
    }
  }
  static Future<void> fixRegionStopCoordinates(String regionId) async {
    try {
      print('🔍 Bölge durakları kontrol ediliyor: $regionId');
      final stopsSnapshot = await _firestore
          .collection('enhanced_stops')
          .where('regionId', isEqualTo: regionId)
          .where('isActive', isEqualTo: true)
          .get();
      int totalStops = stopsSnapshot.docs.length;
      int fixedCount = 0;
      int validCount = 0;
      int errorCount = 0;
      print('📊 Bölge durak sayısı: $totalStops');
      for (final doc in stopsSnapshot.docs) {
        try {
          final data = doc.data();
          final latitude = data['latitude'] as double?;
          final longitude = data['longitude'] as double?;
          final address = data['address'] as String?;
          final stopName = data['name'] as String? ?? 'İsimsiz Durak';
          print('\n🔍 Kontrol ediliyor: $stopName');
          if (latitude == null || longitude == null || 
              latitude == 0.0 || longitude == 0.0) {
            if (address != null && address.trim().isNotEmpty) {
              print('   🔄 Koordinat düzeltiliyor...');
              final coordinates = await GeocodingService.getCoordinatesFromAddress(address);
              if (coordinates != null) {
                await doc.reference.update({
                  'latitude': coordinates['latitude'],
                  'longitude': coordinates['longitude'],
                  'lastUpdated': FieldValue.serverTimestamp(),
                  'coordinatesFixed': true,
                });
                fixedCount++;
                print('   ✅ Düzeltildi: (${coordinates['latitude']}, ${coordinates['longitude']})');
              } else {
                errorCount++;
                print('   ❌ Koordinat alınamadı');
              }
            } else {
              errorCount++;
              print('   ❌ Adres bilgisi eksik');
            }
          } else {
            validCount++;
            print('   ✅ Geçerli');
          }
        } catch (e) {
          errorCount++;
          print('   ❌ Hata: $e');
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
      print('\n🎉 Bölge koordinat düzeltme tamamlandı!');
      print('📊 ÖZET:');
      print('   Düzeltilen: $fixedCount');
      print('   Geçerli: $validCount');
      print('   Hata: $errorCount');
    } catch (e) {
      print('❌ Bölge koordinat düzeltme hatası: $e');
    }
  }
  static Future<bool> fixSingleStopCoordinates(String stopId) async {
    try {
      final stopDoc = await _firestore.collection('enhanced_stops').doc(stopId).get();
      if (!stopDoc.exists) {
        print('❌ Durak bulunamadı: $stopId');
        return false;
      }
      final data = stopDoc.data()!;
      final address = data['address'] as String?;
      final stopName = data['name'] as String? ?? 'İsimsiz Durak';
      if (address == null || address.trim().isEmpty) {
        print('❌ Durak adresi boş: $stopName');
        return false;
      }
      print('🔄 Durak koordinatı düzeltiliyor: $stopName');
      print('   Adres: $address');
      final coordinates = await GeocodingService.getCoordinatesFromAddress(address);
      if (coordinates != null) {
        await stopDoc.reference.update({
          'latitude': coordinates['latitude'],
          'longitude': coordinates['longitude'],
          'lastUpdated': FieldValue.serverTimestamp(),
          'coordinatesFixed': true,
        });
        print('✅ Durak koordinatları düzeltildi: (${coordinates['latitude']}, ${coordinates['longitude']})');
        return true;
      }
      print('❌ Durak koordinatları düzeltilemedi');
      return false;
    } catch (e) {
      print('❌ Durak koordinat düzeltme hatası: $e');
      return false;
    }
  }
  static Future<void> showCoordinateStats() async {
    try {
      final stopsSnapshot = await _firestore
          .collection('enhanced_stops')
          .where('isActive', isEqualTo: true)
          .get();
      int totalStops = 0;
      int validCoordinates = 0;
      int invalidCoordinates = 0;
      int missingAddress = 0;
      for (final doc in stopsSnapshot.docs) {
        final data = doc.data();
        totalStops++;
        final latitude = data['latitude'] as double?;
        final longitude = data['longitude'] as double?;
        final address = data['address'] as String?;
        if (latitude == null || longitude == null || 
            latitude == 0.0 || longitude == 0.0) {
          invalidCoordinates++;
          if (address == null || address.trim().isEmpty) {
            missingAddress++;
          }
        } else {
          validCoordinates++;
        }
      }
      print('\n📊 KOORDINAT İSTATİSTİKLERİ:');
      print('   Toplam durak: $totalStops');
      print('   Geçerli koordinat: $validCoordinates');
      print('   Geçersiz koordinat: $invalidCoordinates');
      print('   Eksik adres: $missingAddress');
      print('   Düzeltilebilir: ${invalidCoordinates - missingAddress}');
    } catch (e) {
      print('❌ İstatistik alma hatası: $e');
    }
  }
}

// Updated

