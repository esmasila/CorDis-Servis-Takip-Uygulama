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

### 🔐 **Giriş Ekranları**

<div style="display: flex; flex-wrap: wrap; gap: 4px; justify-content: center; margin: 20px 0;">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/login-screenshots/login-screen-1.jpg" width="90" alt="Login Ekranı 1" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/login-screenshots/login-screen-2.jpg" width="90" alt="Login Ekranı 2" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
</div>

**Giriş Ekranı Özellikleri:**
- **Kullanıcı Kimlik Doğrulama**: Güvenli giriş sistemi
- **Rol Bazlı Erişim**: Admin, Şoför ve Yolcu rolleri
- **Modern UI/UX**: Kullanıcı dostu arayüz tasarımı
- **Güvenlik**: Firebase Auth entegrasyonu

---

### 🎛️ **Admin Paneli Ekranları**

#### **1️⃣  Yönetim Paneli & Sistem Kontrolü**
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

**Admin Panel Özellikleri (1. Bölüm):**
- **Mobil Admin Panel**: Hızlı erişim ve mobil uyumlu yönetim
- **Dashboard Kontrolü**: Sistem durumu ve genel bakış
- **Şoför Yönetimi**: Şoför hesap ve yetki yönetimi
- **Kullanıcı Yönetimi**: Yolcu hesap yönetimi
- **Durak Yönetimi**: Durak ekleme, düzenleme ve planlama
- **Bölge Yönetimi**: Servis bölgeleri ve organizasyon
 

#### **2️⃣ Yönetim Paneli & Canlı Takip**
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

**Admin Panel Özellikleri (2. Bölüm):**
- **Servis Takip**: Canlı servis operasyon takibi
- **Mesaj Yönetimi**: Şoför ve yolcu mesajlaşma sistemi
- **Bildirim Yönetimi**: Sistem uyarıları ve bildirimler
- **İzin Yönetimi**: Şoför izinleri ve vardiya planlaması
- **Canlı Harita**: Gerçek zamanlı harita üzerinde takip
- **Şoför Takibi**: Gerçek zamanlı şoför konum takibi
- **Bölge Canlı Takip**: Bölge bazlı servis operasyonları
---

#### **🚗 Şoför Paneli Ekranları**

<div style="display: flex; flex-wrap: wrap; gap: 4px; justify-content: center; margin: 20px 0;">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/driver-screenshots/IMG-20250825-WA0029.jpg" width="90" alt="Şoför Ana Ekran" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/driver-screenshots/WhatsApp%20G%C3%B6rsel%202025-08-27%20saat%2014.18.17_3a4786dc.jpg" width="90" alt="Şoför Bildirim Sistemi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/driver-screenshots/WhatsApp%20G%C3%B6rsel%202025-08-27%20saat%2014.17.31_d37274db.jpg" width="90" alt="Şoför Rota Takibi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/driver-screenshots/IMG-20250825-WA0032.jpg" width="90" alt="Şoför Durak Yönetimi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
<img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/driver-screenshots/IMG-20250825-WA0030.jpg" width="90" alt="Şoför Harita Görünümü" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
</div>


**Şoför Panel Özellikleri:**
- **Ana Ekran**: Hızlı erişim menüsü ve durum bilgileri
- **Harita Görünümü**: Canlı rota takibi ve durak konumları
- **Durak Yönetimi**: Durak ziyaretleri ve bekleme süreleri
- **Rota Takibi**: Gerçek zamanlı rota optimizasyonu
- **Bildirim Sistemi**: Yolcu mesajları ve sistem uyarıları

#### **👥 Yolcu Ekranları**

<div style="display: flex; flex-wrap: wrap; gap: 4px; justify-content: center; margin: 20px 0;">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/passenger-screenshots/IMG-20250827-WA0018.jpg" width="90" alt="Yolcu Rota Detayları" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/passenger-screenshots/IMG-20250827-WA0017.jpg" width="90" alt="Yolcu Profil Yönetimi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/passenger-screenshots/IMG-20250827-WA0019.jpg" width="90" alt="Yolcu ETA Hesaplama" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/passenger-screenshots/IMG-20250825-WA0038.jpg" width="90" alt="Yolcu Mesajlaşma" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/passenger-screenshots/IMG-20250825-WA0034.jpg" width="90" alt="Yolcu Ana Ekran" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/passenger-screenshots/IMG-20250825-WA0039.jpg" width="90" alt="Yolcu Bildirim Ayarları" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/passenger-screenshots/IMG-20250825-WA0037.jpg" width="90" alt="Yolcu Durak Bilgileri" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/passenger-screenshots/IMG-20250825-WA0036.jpg" width="90" alt="Yolcu Harita Görünümü" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/passenger-screenshots/IMG-20250825-WA0035.jpg" width="90" alt="Yolcu Servis Takibi" style="border-radius: 6px; box-shadow: 0 2px 6px rgba(0,0,0,0.1);">
</div>

**Yolcu Panel Özellikleri:**
- **Ana Ekran**: Hızlı erişim menüsü ve servis durumu
- **Servis Takibi**: Gerçek zamanlı servis konumu ve rota takibi
- **Harita Görünümü**: Canlı harita üzerinde servis takibi
- **Durak Bilgileri**: Durak konumları ve varış süreleri
- **Mesajlaşma**: Şoför ve diğer yolcularla iletişim
- **Bildirim Ayarları**: ETA uyarıları ve sistem bildirimleri
- **Profil Yönetimi**: Kişisel bilgiler ve tercihler
- **Rota Detayları**: Detaylı rota bilgileri ve alternatifler
- **ETA Hesaplama**: Tahmini varış süresi hesaplama

---

## 🔥 **Firebase Console & Veritabanı Yönetimi**

### **Firebase Console Ekranları**

<div style="display: flex; flex-wrap: wrap; gap: 10px; justify-content: center; margin: 20px 0;">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/firebase-screenshots/firebase-console-1.png" width="200" alt="Firebase Console 1" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/firebase-screenshots/firebase-console-2.png" width="200" alt="Firebase Console 2" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/firebase-screenshots/firebase-console-3.png" width="200" alt="Firebase Console 3" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15);">
  <img src="https://raw.githubusercontent.com/esmasila/CorDis-Servis-Takip-Uygulama/main/docs/firebase-screenshots/firebase-console-4.png" width="200" alt="Firebase Console 4" style="border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.15);">
</div>

**Firebase Console Özellikleri:**
- **Firestore Veritabanı**: NoSQL veritabanı yönetimi
- **Kullanıcı Kimlik Doğrulama**: Firebase Auth yönetimi
- **Cloud Storage**: Dosya depolama yönetimi

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

---

## 📈 Roadmap

- [ ] **v2.0**: AI destekli rota optimizasyonu
- [ ] **v2.1**: Çoklu dil desteği
- [ ] **v2.2**: Gelişmiş analitik dashboard
- [ ] **v2.3**: IoT cihaz entegrasyonu
- [ ] **v2.4**: Blockchain tabanlı güvenlik





// Updated Again

