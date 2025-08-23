# 🚌 Servis Takip Uygulaması - Proje Kuralları

## 📋 İçindekiler
1. [Proje Genel Bakış](#proje-genel-bakış)
2. [Mimari Yapı](#mimari-yapı)
3. [Kodlama Standartları](#kodlama-standartları)
4. [Dosya Organizasyonu](#dosya-organizasyonu)
5. [Güvenlik Kuralları](#güvenlik-kuralları)
6. [Performans Kuralları](#performans-kuralları)
7. [UI/UX Kuralları](#uiux-kuralları)
8. [Test Kuralları](#test-kuralları)
9. [Deployment Kuralları](#deployment-kuralları)

---

## 🎯 Proje Genel Bakış

### Uygulama Türü
- **Platform**: Flutter (Cross-platform)
- **Backend**: Firebase (Firestore, Auth, Storage, Messaging)
- **Harita**: Google Maps API
- **Konum**: Geolocator, Background Location Service
- **Bildirimler**: Firebase Cloud Messaging, Local Notifications

### Kullanıcı Rolleri
1. **Admin**: Sistem yönetimi, kullanıcı yönetimi, raporlama
2. **Şoför**: Araç takibi, durak yönetimi, rota optimizasyonu
3. **Yolcu**: Servis takibi, yakınlık bildirimleri, mesajlaşma

---

## 🏗️ Mimari Yapı

### Klasör Yapısı
```
lib/
├── main.dart                 # Uygulama giriş noktası
├── firebase_options.dart     # Firebase konfigürasyonu
├── models/                   # Veri modelleri
├── service/                  # İş mantığı servisleri
├── admin/                    # Admin paneli ekranları
├── driver/                   # Şoför ekranları
├── passenger/                # Yolcu ekranları
├── view/                     # Ortak ekranlar (login, signup)
├── widget/                   # Yeniden kullanılabilir widget'lar
└── utils/                    # Yardımcı fonksiyonlar
```

### Servis Katmanı
- **AuthService**: Kimlik doğrulama ve yetkilendirme
- **LocationService**: Konum takibi ve güncelleme
- **NotificationService**: Bildirim yönetimi
- **CacheService**: Yerel veri önbellekleme
- **BackgroundLocationService**: Arka plan konum takibi
- **UserSession**: Kullanıcı oturum yönetimi

---

## 📝 Kodlama Standartları

### Genel Kurallar
1. **Dil**: Tüm kodlar Türkçe yorum ve değişken isimleri ile yazılmalı
2. **Indentation**: 2 space kullanılmalı
3. **Satır Uzunluğu**: Maksimum 80 karakter
4. **Dosya Uzunluğu**: Maksimum 500 satır (gerekirse bölünmeli)

### Naming Conventions
```dart
// Sınıf isimleri: PascalCase
class UserModel { }

// Değişken isimleri: camelCase
String userName = "Ahmet";

// Sabitler: UPPER_SNAKE_CASE
const String API_BASE_URL = "https://api.example.com";

// Dosya isimleri: snake_case
user_model.dart
location_service.dart
```

### Kod Yapısı
```dart
// 1. Import'lar (sıralı)
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/user_model.dart';

// 2. Sınıf tanımı
class ExampleService {
  // 3. Private değişkenler
  static ExampleService? _instance;
  
  // 4. Constructor
  ExampleService._();
  
  // 5. Factory constructor
  factory ExampleService() => instance;
  
  // 6. Public metodlar
  Future<void> exampleMethod() async {
    try {
      // İş mantığı
    } catch (e) {
      print('❌ Hata: $e');
    }
  }
}
```

### Hata Yönetimi
```dart
// Her zaman try-catch kullan
try {
  await someAsyncOperation();
} catch (e) {
  print('❌ Hata: $e');
  // Kullanıcıya uygun mesaj göster
  showErrorMessage(context, 'İşlem başarısız oldu');
}
```

### Logging
```dart
// Başarılı işlemler
print('✅ Kullanıcı başarıyla giriş yaptı');

// Hatalar
print('❌ Giriş hatası: $error');

// Bilgilendirme
print('📱 Uygulama başlatılıyor...');
```

---

## 📁 Dosya Organizasyonu

### Model Dosyaları
- Her model için ayrı dosya
- `fromMap`, `toMap`, `copyWith` metodları zorunlu
- Firestore entegrasyonu için `fromFirestore` metodu

```dart
class UserModel {
  final String id;
  final String name;
  final String email;
  final String role;
  
  // Constructor, factory methods, toMap, copyWith...
}
```

### Service Dosyaları
- Singleton pattern kullan
- Async/await tercih et
- Error handling ekle
- Cache mekanizması kullan

### Screen Dosyaları
- StatefulWidget tercih et (konum takibi için)
- initState'de async işlemleri yap
- dispose'da subscription'ları temizle
- setState kullanımını minimize et

---

## 🔒 Güvenlik Kuralları

### Firebase Güvenliği
1. **Firestore Rules**: Her koleksiyon için özel kurallar
2. **Authentication**: Email doğrulama zorunlu
3. **Role-based Access**: Kullanıcı rollerine göre erişim
4. **Data Validation**: Tüm veriler server-side validate edilmeli

### Konum Güvenliği
1. **Permission Check**: Konum izni kontrolü
2. **Data Encryption**: Hassas veriler şifrelenmeli
3. **Background Limits**: Arka plan konum takibi sınırlı olmalı

### Kod Güvenliği
```dart
// API key'leri asla kodda tutma
// ❌ Yanlış
const String API_KEY = "sk-123456789";

// ✅ Doğru - Environment variables kullan
final apiKey = const String.fromEnvironment('API_KEY');
```

---

## ⚡ Performans Kuralları

### Memory Management
1. **StreamSubscription**: dispose'da mutlaka cancel et
2. **Image Caching**: Büyük resimler cache'le
3. **List Optimization**: ListView.builder kullan
4. **Background Tasks**: Workmanager ile optimize et

### Network Optimization
1. **Batch Operations**: Firestore batch işlemleri kullan
2. **Pagination**: Büyük listeler için sayfalama
3. **Offline Support**: Cache ile offline çalışma
4. **Request Limiting**: API çağrılarını sınırla

### Code Optimization
```dart
// ❌ Yanlış - Her build'de yeni widget
Widget build(BuildContext context) {
  return Container(
    child: Text('Hello'),
  );
}

// ✅ Doğru - const kullan
Widget build(BuildContext context) {
  return const Container(
    child: Text('Hello'),
  );
}
```

---

## 🎨 UI/UX Kuralları

### Tema Standartları
```dart
// Ana renkler
primaryColor: Colors.deepPurple
secondaryColor: Colors.blue
accentColor: Colors.orange

// Typography
headline1: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
bodyText1: TextStyle(fontSize: 16)
```

### Responsive Design
1. **MediaQuery**: Ekran boyutuna göre uyarlama
2. **Flexible Widgets**: Flexible, Expanded kullan
3. **Orientation**: Portrait/Landscape desteği
4. **Accessibility**: Screen reader desteği

### Loading States
```dart
// Her async işlem için loading göster
if (isLoading) {
  return const Center(child: CircularProgressIndicator());
}
```

### Error Handling
```dart
// Kullanıcı dostu hata mesajları
void showErrorMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
    ),
  );
}
```

---

## 🧪 Test Kuralları

### Unit Tests
- Her service için unit test yaz
- Model sınıfları için test coverage %90+
- Mock kullanarak external dependencies test et

### Widget Tests
- Kritik UI componentleri için widget test
- User interaction testleri
- Navigation testleri

### Integration Tests
- End-to-end user flow testleri
- Firebase integration testleri
- Performance testleri

---

## 🚀 Deployment Kuralları

### Build Configuration
1. **Release Mode**: Production build'leri release mode'da
2. **Code Obfuscation**: ProGuard/R8 kullan
3. **Asset Optimization**: Resimleri optimize et
4. **Version Management**: Semantic versioning kullan

### Firebase Configuration
1. **Environment**: Dev/Staging/Production ayrımı
2. **Security Rules**: Production'da strict rules
3. **Monitoring**: Crashlytics ve Analytics
4. **Backup**: Regular data backup

### App Store Guidelines
1. **Privacy Policy**: GDPR uyumlu
2. **App Store Metadata**: Türkçe açıklamalar
3. **Screenshots**: Tüm ekran boyutları için
4. **Rating**: Age-appropriate rating

---

## 📋 Checklist

### Geliştirme Öncesi
- [ ] Feature branch oluştur
- [ ] Requirements dokümante et
- [ ] UI/UX mockup hazırla
- [ ] Test planı oluştur

### Geliştirme Sırasında
- [ ] Kod standartlarına uy
- [ ] Error handling ekle
- [ ] Loading states ekle
- [ ] Türkçe yorumlar yaz
- [ ] Performance optimize et

### Geliştirme Sonrası
- [ ] Unit testleri yaz
- [ ] Widget testleri yaz
- [ ] Code review yap
- [ ] Documentation güncelle
- [ ] Performance test et

### Deployment Öncesi
- [ ] Security audit yap
- [ ] Performance test et
- [ ] UI/UX review yap
- [ ] App store guidelines kontrol et
- [ ] Backup al

---

## 🔄 Güncelleme Süreci

Bu doküman sürekli güncellenmelidir:
1. Yeni teknolojiler eklendiğinde
2. Mimari değişiklikler olduğunda
3. Team feedback'leri alındığında
4. Best practices değiştiğinde

**Son Güncelleme**: 2024
**Versiyon**: 1.0
**Geliştirici**: Servis Takip Uygulaması Ekibi
