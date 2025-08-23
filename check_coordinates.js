const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Firebase Admin SDK'yı başlat
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkCoordinates() {
  try {
    console.log('🔍 Enhanced_stops koleksiyonundaki koordinatları kontrol ediliyor...');
    
    const stopsSnapshot = await db.collection('enhanced_stops').get();
    
    let totalStops = 0;
    let invalidCoordinates = 0;
    let validCoordinates = 0;
    
    stopsSnapshot.forEach(doc => {
      const data = doc.data();
      totalStops++;
      
      const lat = data.latitude;
      const lng = data.longitude;
      
      if (lat === 0.0 || lng === 0.0 || lat == null || lng == null) {
        invalidCoordinates++;
        console.log(`❌ Geçersiz koordinat: ${doc.id} - ${data.address || 'Adres yok'} (${lat}, ${lng})`);
      } else {
        validCoordinates++;
        console.log(`✅ Geçerli koordinat: ${doc.id} - ${data.address || 'Adres yok'} (${lat}, ${lng})`);
      }
    });
    
    console.log('\n📊 ÖZET:');
    console.log(`Toplam durak: ${totalStops}`);
    console.log(`Geçerli koordinat: ${validCoordinates}`);
    console.log(`Geçersiz koordinat: ${invalidCoordinates}`);
    
    if (invalidCoordinates > 0) {
      console.log('\n🔧 Geçersiz koordinatları düzeltmek için geocoding servisi çalıştırılmalı.');
    }
    
  } catch (error) {
    console.error('❌ Hata:', error);
  } finally {
    process.exit(0);
  }
}

checkCoordinates();