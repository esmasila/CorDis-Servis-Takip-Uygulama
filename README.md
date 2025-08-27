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

### 🎛️ **Admin Paneli Ekranları**

#### **1️⃣ Canlı Takip & Monitoring Ekranları**
<div style="display: flex; flex-wrap: wrap; gap: 4px; justify-content: center; margin: 20px 0;">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0013.jpg" width="90" alt="Mobil Admin Panel" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/WhatsApp%20Görsel%202025-08-25%20saat%2019.13.51_24674f5e.jpg" width="90" alt="WhatsApp Görsel 2" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/WhatsApp%20Görsel%202025-08-25%20saat%2019.13.51_9981926a.jpg" width="90" alt="WhatsApp Görsel 1" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0015.jpg" width="90" alt="Şoför Takibi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0014.jpg" width="90" alt="Bölge Canlı Takip" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0017.jpg" width="90" alt="İzin Yönetimi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0016.jpg" width="90" alt="Canlı Harita" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0018.jpg" width="90" alt="Bildirim Yönetimi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
</div>
*Canlı takip ve monitoring ekranları - Mobil panel, WhatsApp entegrasyonu, şoför takibi, bölge izleme, izin yönetimi, canlı harita ve bildirim sistemi*

**Detaylı Açıklama:** Bu bölümde servis takip sisteminin canlı izleme özellikleri bulunur. Mobil admin panel ile cep telefonundan yönetim, WhatsApp entegrasyonu ile anlık iletişim, şoför takibinde gerçek zamanlı konum izleme, bölge canlı takipte servis alanı monitoring, izin yönetiminde çalışan izin takibi, canlı haritada servis konumları ve bildirim yönetiminde push bildirim sistemi yer alır.

#### **2️⃣ Yönetim Paneli & Sistem Kontrolü**
<div style="display: flex; flex-wrap: wrap; gap: 4px; justify-content: center; margin: 20px 0;">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0019.jpg" width="90" alt="Mesaj Yönetimi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0020.jpg" width="90" alt="Servis Takip" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0021.jpg" width="90" alt="Bölge Yönetimi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0022.jpg" width="90" alt="Durak Yönetimi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0023.jpg" width="90" alt="Kullanıcı Yönetimi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0024.jpg" width="90" alt="Şoför Yönetimi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0025.jpg" width="90" alt="Admin Panel Drawer Menü" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/admin-screenshots/IMG-20250825-WA0026.jpg" width="90" alt="Admin Ana Dashboard" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
</div>
*Yönetim paneli ve sistem kontrolü - Mesaj sistemi, servis takip, bölge yönetimi, durak yönetimi, kullanıcı yönetimi, şoför yönetimi, navigasyon menü ve ana dashboard*

**Detaylı Açıklama:** Bu bölümde sistem yönetiminin temel kontrol ekranları bulunur. Mesaj yönetiminde şoför-yolcu iletişim sistemi, servis takip ekranında aktif servisler ve durak sıralaması, bölge yönetiminde servis alanları ve bölge tanımları, durak yönetiminde servis noktaları ve konum bilgileri, kullanıcı yönetiminde çalışan kayıtları ve yetkilendirme, şoför yönetiminde sürücü bilgileri ve araç atamaları, drawer menüde navigasyon seçenekleri ve ana dashboard'da sistem durumu, istatistikler ve genel bakış bulunur.

---

### 📱 **Şoför & Yolcu Ekranları**

> 📸 Şoför ve yolcu ekran görüntüleri buraya eklenecek

---

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

## 🎮 Simülasyon Modu Kullanımı

### **Basit Simülasyon Başlatma**
```dart
import 'package:your_app/service/simulation_service.dart';

// Rota noktaları tanımlayın
List<LatLng> route = [
  LatLng(38.7205, 35.4826), // Kayseri
  LatLng(38.7205, 35.4826), // Hedef
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

## 📈 Roadmap

- [ ] **v2.0**: AI destekli rota optimizasyonu
- [ ] **v2.1**: Çoklu dil desteği
- [ ] **v2.2**: Gelişmiş analitik dashboard
- [ ] **v2.3**: IoT cihaz entegrasyonu
- [ ] **v2.4**: Blockchain tabanlı güvenlik

---

