# 🚌 CORDIS - Servis Takip Sistemi

[![Flutter](https://img.shields.io/badge/Flutter-3.1.0+-blue.svg)](https://flutter.dev/)
[![Firebase](https://img.shields.io/badge/Firebase-Cloud-orange.svg)](https://firebase.google.com/)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-brightgreen.svg)](https://flutter.dev/multi-platform)

Modern ve gelişmiş bir servis takip sistemi. Şoförlerin konumlarını gerçek zamanlı takip edin, yolculara ETA bilgisi verin ve servis operasyonlarını optimize edin.

## ✨ Özellikler

### 🎯 **Ana Özellikler**
- **Gerçek Zamanlı Takip**: Şoför konumlarını canlı olarak izleyin
- **Akıllı ETA Hesaplama**: Google Maps API ile trafik verisi entegrasyonu
- **Çoklu Platform**: Android, iOS, Web, macOS ve Windows desteği
- **Offline Çalışma**: İnternet bağlantısı olmadan da temel özellikler
- **Push Bildirimler**: Anlık güncellemeler ve uyarılar

### 🚗 **Şoför Özellikleri**
- **Konum Paylaşımı**: Gerçek zamanlı konum güncellemesi
- **Rota Optimizasyonu**: TSP algoritması ile en verimli rota
- **Durak Yönetimi**: Durak ziyaretleri ve bekleme süreleri
- **Mesajlaşma**: Yolcular ve yöneticilerle iletişim

### 👥 **Yolcu Özellikleri**
- **Servis Takibi**: Servisin nerede olduğunu görün
- **Varış Zamanı**: Tahmini varış süresi hesaplama
- **Mesafe Uyarıları**: Servise yaklaştığında bildirim
- **Chat Sistemi**: Şoför ve diğer yolcularla iletişim

### 🎮 **Simülasyon Modu**
- **Test Senaryoları**: Gerçekçi şoför hareket simülasyonu
- **Rota Simülasyonu**: Önceden tanımlanmış rotalarda test
- **Hız Kontrolü**: Ayarlanabilir simülasyon hızı
- **Durak Ziyaretleri**: Otomatik durak yaklaşma simülasyonu

### 🔧 **Yönetici Paneli**
- **Şoför Yönetimi**: Şoför ekleme, düzenleme, silme
- **Bölge Yönetimi**: Servis bölgelerini organize edin
- **Rota Planlama**: Durak sıralaması ve optimizasyon
- **İstatistikler**: Performans metrikleri ve raporlar

## 🛠️ Teknoloji Stack

### **Frontend & UI**
- **Flutter 3.1.0+**: Cross-platform UI framework
- **Material Design**: Modern ve kullanıcı dostu arayüz
- **Provider**: State management
- **Google Maps**: Harita entegrasyonu

### **Backend & Veritabanı**
- **Firebase Firestore**: NoSQL veritabanı
- **Firebase Auth**: Kullanıcı kimlik doğrulama
- **Firebase Storage**: Dosya depolama
- **Firebase Messaging**: Push bildirimler

### **Harita & Konum Servisleri**
- **Google Maps API**: Harita ve yönlendirme
- **Geolocator**: Konum servisleri
- **Directions API**: Rota hesaplama
- **Route Optimization**: TSP algoritması

### **Background Processing**
- **WorkManager**: Android background tasks
- **Background Service**: iOS background processing
- **Location Updates**: Sürekli konum takibi

## 📱 Ekran Görüntüleri

> 📸 Ekran görüntüleri buraya eklenecek

## 🚀 Kurulum

### **Gereksinimler**
- Flutter SDK 3.1.0 veya üzeri
- Dart SDK 3.0.0 veya üzeri
- Android Studio / VS Code
- Firebase hesabı

### **1. Repository'yi Klonlayın**
```bash
git clone https://github.com/kullaniciadi/servistakipapp.git
cd servistakipapp
```

### **2. Bağımlılıkları Yükleyin**
```bash
flutter pub get
```

### **3. Firebase Yapılandırması**
```bash
# Firebase CLI kurulumu
npm install -g firebase-tools

# Firebase'e giriş yapın
firebase login

# Proje yapılandırması
firebase init
```

### **4. API Anahtarlarını Ayarlayın**
`lib/firebase_options.dart` dosyasında Firebase yapılandırmasını güncelleyin.

### **5. Uygulamayı Çalıştırın**
```bash
# Android
flutter run

# iOS
flutter run -d ios

# Web
flutter run -d chrome
```

## 📁 Proje Yapısı

```
lib/
├── admin/                 # Yönetici paneli
├── driver/               # Şoför ekranları
├── passenger/            # Yolcu ekranları
├── models/               # Veri modelleri
├── providers/            # State management
├── service/              # Business logic servisleri
├── utils/                # Yardımcı fonksiyonlar
├── view/                 # Ana ekranlar
└── widget/               # Yeniden kullanılabilir widget'lar
```

## 🔧 Konfigürasyon

### **Environment Variables**
```dart
// lib/service/route_optimization_service.dart
static const String _googleMapsApiKey = 'YOUR_API_KEY';
static const String _firebaseFunctionsUrl = 'YOUR_FUNCTIONS_URL';
```

### **Firebase Rules**
```javascript
// firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Güvenlik kuralları burada
  }
}
```

## 🎮 Simülasyon Modu Kullanımı

### **Basit Simülasyon Başlatma**
```dart
import 'package:your_app/service/simulation_service.dart';

// Rota noktaları tanımlayın
List<LatLng> route = [
  LatLng(41.0082, 28.9784), // İstanbul
  LatLng(41.0082, 28.9784), // Hedef
];

// Simülasyonu başlatın
await SimulationService.startDriverSimulation(
  driverId: 'driver123',
  route: route,
  speed: 40.0, // km/h
  interval: Duration(seconds: 1),
);
```

### **Rastgele Rota Oluşturma**
```dart
// Merkez nokta etrafında rastgele rota
List<LatLng> randomRoute = SimulationService.generateRandomRoute(
  center: LatLng(41.0082, 28.9784),
  pointCount: 10,
  radiusKm: 5.0,
);
```

### **Simülasyon Durumu Kontrolü**
```dart
if (SimulationService.isSimulationActive) {
  print('Simülasyon aktif');
  print('Mevcut konum: ${SimulationService.currentLocation}');
  print('İlerleme: ${SimulationService.routeProgress * 100}%');
}
```

## 📊 API Referansı

### **SimulationService**
| Method | Açıklama | Parametreler |
|--------|----------|--------------|
| `startDriverSimulation` | Simülasyon başlatır | `driverId`, `route`, `speed`, `interval` |
| `stopSimulation` | Simülasyonu durdurur | - |
| `generateRandomRoute` | Rastgele rota oluşturur | `center`, `pointCount`, `radiusKm` |

### **ETACalculationService**
| Method | Açıklama | Parametreler |
|--------|----------|--------------|
| `calculateETA` | Varış süresi hesaplar | `driverLocation`, `passengerStop`, `remainingStops` |

## 🧪 Test

### **Unit Tests**
```bash
flutter test
```

### **Integration Tests**
```bash
flutter test integration_test/
```

### **Widget Tests**
```bash
flutter test test/widget_test.dart
```

## 📦 Build & Deploy

### **Android APK**
```bash
flutter build apk --release
```

### **iOS IPA**
```bash
flutter build ios --release
```

### **Web Build**
```bash
flutter build web --release
```

## 📈 Roadmap

- [ ] **v2.0**: AI destekli rota optimizasyonu
- [ ] **v2.1**: Çoklu dil desteği
- [ ] **v2.2**: Gelişmiş analitik dashboard
- [ ] **v2.3**: IoT cihaz entegrasyonu
- [ ] **v2.4**: Blockchain tabanlı güvenlik

---

## 📞 İletişim

Proje hakkında sorularınız için lütfen iletişime geçin.
