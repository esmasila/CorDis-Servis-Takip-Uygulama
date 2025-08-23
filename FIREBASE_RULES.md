# 🔥 Firebase Güvenlik Kuralları

## 📋 İçindekiler
1. [Genel Güvenlik Prensipleri](#genel-güvenlik-prensipleri)
2. [Firestore Security Rules](#firestore-security-rules)
3. [Authentication Kuralları](#authentication-kuralları)
4. [Storage Kuralları](#storage-kuralları)
5. [Functions Güvenliği](#functions-güvenliği)
6. [Monitoring ve Logging](#monitoring-ve-logging)

---

## 🛡️ Genel Güvenlik Prensipleri

### 1. Defense in Depth
- Çok katmanlı güvenlik yaklaşımı
- Her seviyede güvenlik kontrolü
- Fail-safe prensibi

### 2. Least Privilege
- Minimum yetki prensibi
- Sadece gerekli erişimler
- Role-based access control

### 3. Data Validation
- Client-side validation
- Server-side validation
- Input sanitization

---

## 🔥 Firestore Security Rules

### Kullanıcılar Koleksiyonu
```javascript
// users collection
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      // Kullanıcı sadece kendi verilerini okuyabilir
      allow read: if request.auth != null && request.auth.uid == userId;
      
      // Kullanıcı sadece kendi verilerini güncelleyebilir
      allow update: if request.auth != null && 
                      request.auth.uid == userId &&
                      request.resource.data.diff(resource.data).affectedKeys()
                        .hasOnly(['name', 'email', 'phone', 'profileImageUrl', 'updatedAt']);
      
      // Yeni kullanıcı kaydı - sadece gerekli alanlar
      allow create: if request.auth != null && 
                     request.auth.uid == userId &&
                     request.resource.data.keys().hasOnly(['name', 'email', 'role', 'regionId', 'createdAt']) &&
                     request.resource.data.role in ['Admin', 'Şoför', 'Yolcu'];
      
      // Silme işlemi - sadece admin
      allow delete: if request.auth != null && 
                     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'Admin';
    }
  }
}
```

### Şoförler Koleksiyonu
```javascript
// drivers collection
match /drivers/{driverId} {
  // Şoför kendi verilerini okuyabilir
  allow read: if request.auth != null && 
                (request.auth.uid == driverId || 
                 get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'Admin');
  
  // Şoför kendi verilerini güncelleyebilir
  allow update: if request.auth != null && 
                  request.auth.uid == driverId &&
                  request.resource.data.diff(resource.data).affectedKeys()
                    .hasOnly(['vehiclePlate', 'isActive', 'currentLocation', 'lastUpdated']);
  
  // Admin şoför ekleyebilir
  allow create: if request.auth != null && 
                 get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'Admin';
  
  // Admin şoför silebilir
  allow delete: if request.auth != null && 
                 get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'Admin';
}
```

### Duraklar Koleksiyonu
```javascript
// stops collection
match /stops/{stopId} {
  // Tüm kullanıcılar durak bilgilerini okuyabilir
  allow read: if request.auth != null;
  
  // Sadece admin durak ekleyebilir/güncelleyebilir
  allow write: if request.auth != null && 
                 get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'Admin';
}
```

### Bölgeler Koleksiyonu
```javascript
// regions collection
match /regions/{regionId} {
  // Tüm kullanıcılar bölge bilgilerini okuyabilir
  allow read: if request.auth != null;
  
  // Sadece admin bölge ekleyebilir/güncelleyebilir
  allow write: if request.auth != null && 
                 get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'Admin';
}
```

### Mesajlar Koleksiyonu
```javascript
// messages collection
match /messages/{messageId} {
  // Kullanıcı sadece kendi mesajlarını okuyabilir
  allow read: if request.auth != null && 
                (resource.data.senderId == request.auth.uid || 
                 resource.data.receiverId == request.auth.uid);
  
  // Kullanıcı mesaj gönderebilir
  allow create: if request.auth != null && 
                 request.resource.data.senderId == request.auth.uid &&
                 request.resource.data.keys().hasOnly(['senderId', 'receiverId', 'message', 'timestamp', 'isRead']);
  
  // Mesaj durumu güncellenebilir
  allow update: if request.auth != null && 
                  request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isRead']) &&
                  (resource.data.senderId == request.auth.uid || 
                   resource.data.receiverId == request.auth.uid);
}
```

### Konum Geçmişi Koleksiyonu
```javascript
// location_history collection
match /location_history/{historyId} {
  // Kullanıcı sadece kendi konum geçmişini okuyabilir
  allow read: if request.auth != null && 
                resource.data.userId == request.auth.uid;
  
  // Kullanıcı kendi konumunu kaydedebilir
  allow create: if request.auth != null && 
                 request.resource.data.userId == request.auth.uid &&
                 request.resource.data.keys().hasOnly(['userId', 'latitude', 'longitude', 'timestamp', 'accuracy']);
}
```

---

## 🔐 Authentication Kuralları

### Email Doğrulama
```javascript
// Firebase Auth Rules
{
  "rules": {
    ".read": "auth != null && auth.token.email_verified == true",
    ".write": "auth != null && auth.token.email_verified == true"
  }
}
```

### Role-based Access
```javascript
// Kullanıcı rolü kontrolü
function isAdmin() {
  return request.auth != null && 
         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'Admin';
}

function isDriver() {
  return request.auth != null && 
         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'Şoför';
}

function isPassenger() {
  return request.auth != null && 
         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'Yolcu';
}
```

### Bölge Bazlı Erişim
```javascript
// Kullanıcının bölgesi kontrolü
function userInRegion(regionId) {
  return request.auth != null && 
         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.regionId == regionId;
}
```

---

## 📁 Storage Kuralları

### Profil Resimleri
```javascript
// Firebase Storage Rules
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Profil resimleri
    match /profile_images/{userId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
                     request.auth.uid == userId &&
                     request.resource.size < 5 * 1024 * 1024 && // 5MB limit
                     request.resource.contentType.matches('image/.*');
    }
    
    // Dökümanlar
    match /documents/{userId}/{allPaths=**} {
      allow read: if request.auth != null && 
                    (request.auth.uid == userId || isAdmin());
      allow write: if request.auth != null && 
                     request.auth.uid == userId &&
                     request.resource.size < 10 * 1024 * 1024; // 10MB limit
    }
  }
}
```

---

## ⚡ Functions Güvenliği

### Cloud Functions Security
```javascript
// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Admin SDK başlat
admin.initializeApp();

// Güvenli HTTP function
exports.secureFunction = functions.https.onCall((data, context) => {
  // Kullanıcı doğrulama
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Kullanıcı girişi gerekli');
  }
  
  // Role kontrolü
  const userRecord = await admin.firestore()
    .collection('users')
    .doc(context.auth.uid)
    .get();
    
  if (!userRecord.exists) {
    throw new functions.https.HttpsError('permission-denied', 'Kullanıcı bulunamadı');
  }
  
  const userData = userRecord.data();
  if (userData.role !== 'Admin') {
    throw new functions.https.HttpsError('permission-denied', 'Yetkisiz erişim');
  }
  
  // İş mantığı
  return { success: true };
});
```

### Background Functions
```javascript
// Arka plan işlemleri
exports.cleanupOldData = functions.pubsub.schedule('every 24 hours').onRun(async (context) => {
  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - 30); // 30 gün önce
    
    const snapshot = await admin.firestore()
      .collection('location_history')
      .where('timestamp', '<', cutoffDate)
      .get();
      
    const batch = admin.firestore().batch();
    snapshot.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });
    
    await batch.commit();
    console.log('✅ Eski veriler temizlendi');
  } catch (error) {
    console.error('❌ Temizleme hatası:', error);
  }
});
```

---

## 📊 Monitoring ve Logging

### Firestore Monitoring
```javascript
// Firestore audit logging
exports.auditLog = functions.firestore
  .document('users/{userId}')
  .onWrite((change, context) => {
    const beforeData = change.before.data();
    const afterData = change.after.data();
    
    console.log('📝 Kullanıcı değişikliği:', {
      userId: context.params.userId,
      before: beforeData,
      after: afterData,
      timestamp: new Date().toISOString()
    });
  });
```

### Error Tracking
```javascript
// Hata takibi
exports.errorHandler = functions.https.onRequest((req, res) => {
  try {
    // İş mantığı
    res.json({ success: true });
  } catch (error) {
    console.error('❌ Function hatası:', error);
    
    // Hata detaylarını logla
    const errorLog = {
      function: 'errorHandler',
      error: error.message,
      stack: error.stack,
      timestamp: new Date().toISOString(),
      requestData: req.body
    };
    
    // Firestore'a hata logunu kaydet
    admin.firestore().collection('error_logs').add(errorLog);
    
    res.status(500).json({ 
      error: 'İşlem başarısız oldu',
      code: 'INTERNAL_ERROR'
    });
  }
});
```

---

## 🔍 Güvenlik Kontrol Listesi

### Firestore Rules
- [ ] Tüm koleksiyonlar için kurallar tanımlandı
- [ ] Role-based access control uygulandı
- [ ] Data validation eklendi
- [ ] Input sanitization yapıldı
- [ ] Rate limiting uygulandı

### Authentication
- [ ] Email doğrulama zorunlu
- [ ] Password complexity kuralları
- [ ] Account lockout mekanizması
- [ ] Session timeout ayarlandı
- [ ] Multi-factor authentication (opsiyonel)

### Storage
- [ ] File size limits tanımlandı
- [ ] File type validation eklendi
- [ ] Access control kuralları
- [ ] Virus scanning (opsiyonel)
- [ ] Backup strategy

### Functions
- [ ] Input validation eklendi
- [ ] Error handling uygulandı
- [ ] Rate limiting eklendi
- [ ] Logging mekanizması
- [ ] Monitoring alerts

### Monitoring
- [ ] Error tracking aktif
- [ ] Performance monitoring
- [ ] Security alerts
- [ ] Audit logging
- [ ] Backup monitoring

---

## 🚨 Güvenlik Alarmları

### Suspicious Activity Detection
```javascript
// Şüpheli aktivite tespiti
exports.detectSuspiciousActivity = functions.firestore
  .document('users/{userId}')
  .onWrite((change, context) => {
    const afterData = change.after.data();
    
    // Çok fazla giriş denemesi
    if (afterData.loginAttempts > 5) {
      console.warn('⚠️ Şüpheli giriş denemesi:', context.params.userId);
      
      // Admin'e bildirim gönder
      admin.firestore().collection('alerts').add({
        type: 'suspicious_login',
        userId: context.params.userId,
        timestamp: new Date().toISOString(),
        details: 'Çok fazla giriş denemesi'
      });
    }
  });
```

### Data Breach Detection
```javascript
// Veri sızıntısı tespiti
exports.detectDataBreach = functions.firestore
  .document('users/{userId}')
  .onRead((snapshot, context) => {
    const userData = snapshot.data();
    
    // Yetkisiz erişim kontrolü
    if (context.auth.uid !== context.params.userId) {
      console.warn('🚨 Yetkisiz veri erişimi:', {
        requester: context.auth.uid,
        target: context.params.userId,
        timestamp: new Date().toISOString()
      });
      
      // Güvenlik logunu kaydet
      admin.firestore().collection('security_logs').add({
        type: 'unauthorized_access',
        requester: context.auth.uid,
        target: context.params.userId,
        timestamp: new Date().toISOString()
      });
    }
  });
```

---

## 📋 Deployment Checklist

### Production Deployment
- [ ] Security rules test edildi
- [ ] Authentication kuralları aktif
- [ ] Storage rules uygulandı
- [ ] Functions güvenliği kontrol edildi
- [ ] Monitoring aktif
- [ ] Backup strategy uygulandı
- [ ] Error tracking aktif
- [ ] Performance monitoring aktif
- [ ] Security alerts aktif
- [ ] Audit logging aktif

### Regular Security Audits
- [ ] Monthly security review
- [ ] Quarterly penetration testing
- [ ] Annual security assessment
- [ ] Continuous monitoring
- [ ] Incident response plan

---

## 🔄 Güncelleme Süreci

Bu güvenlik kuralları sürekli güncellenmelidir:
1. Yeni güvenlik açıkları tespit edildiğinde
2. Firebase yeni özellikler eklediğinde
3. Uygulama yeni özellikler eklendiğinde
4. Güvenlik standartları değiştiğinde

**Son Güncelleme**: 2024
**Versiyon**: 1.0
**Güvenlik Seviyesi**: Yüksek
