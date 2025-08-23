# 📝 Servis Takip Uygulaması - Kodlama Kuralları

## 🎯 Genel Prensipler

### 1. Türkçe Önceliği
- Tüm değişken isimleri Türkçe olmalı
- Yorumlar Türkçe yazılmalı
- Hata mesajları Türkçe olmalı
- UI metinleri Türkçe olmalı

### 2. Okunabilirlik
- Kod kendini açıklayıcı olmalı
- Karmaşık işlemler için detaylı yorumlar
- Fonksiyon isimleri açıklayıcı olmalı

### 3. Tutarlılık
- Tüm projede aynı stil kullanılmalı
- Benzer işlemler için benzer yaklaşım
- Standart pattern'ler kullanılmalı

---

## 🏗️ Mimari Kuralları

### Service Pattern
```dart
// ✅ Doğru - Singleton Pattern
class LocationService {
  static LocationService? _instance;
  
  LocationService._();
  
  static LocationService get instance {
    _instance ??= LocationService._();
    return _instance!;
  }
  
  factory LocationService() => instance;
}
```

### Model Pattern
```dart
// ✅ Doğru - Firestore Model
class UserModel {
  final String id;
  final String name;
  final String email;
  final String role;
  
  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });
  
  factory UserModel.fromMap(Map<String, dynamic> data, String id) {
    return UserModel(
      id: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? '',
    );
  }
  
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel.fromMap(data, doc.id);
  }
  
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'role': role,
    };
  }
  
  UserModel copyWith({
    String? name,
    String? email,
    String? role,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
    );
  }
}
```

---

## 📝 Naming Conventions

### Değişken İsimleri
```dart
// ✅ Doğru - camelCase, Türkçe
String kullaniciAdi = "Ahmet";
String kullaniciEmail = "ahmet@example.com";
bool konumPaylasimiAktif = true;
DateTime sonGuncellemeZamani = DateTime.now();

// ❌ Yanlış
String userName = "Ahmet";
String userEmail = "ahmet@example.com";
bool locationSharingActive = true;
```

### Fonksiyon İsimleri
```dart
// ✅ Doğru - camelCase, Türkçe, açıklayıcı
Future<void> kullaniciGirisYap(String email, String sifre) async { }
Future<void> konumGuncelle() async { }
void hataMesajiGoster(String mesaj) { }
bool kullaniciAktifMi() { }

// ❌ Yanlış
Future<void> login(String email, String password) async { }
Future<void> updateLocation() async { }
void showError(String message) { }
```

### Sınıf İsimleri
```dart
// ✅ Doğru - PascalCase, Türkçe
class KullaniciModel { }
class KonumServisi { }
class BildirimYoneticisi { }
class DurakTakipWidget { }

// ❌ Yanlış
class UserModel { }
class LocationService { }
class NotificationManager { }
```

### Dosya İsimleri
```dart
// ✅ Doğru - snake_case, Türkçe
kullanici_model.dart
konum_servisi.dart
bildirim_yoneticisi.dart
durak_takip_widget.dart

// ❌ Yanlış
user_model.dart
location_service.dart
notification_manager.dart
```

---

## 🔧 Kod Yapısı

### Import Sıralaması
```dart
// 1. Dart core imports
import 'dart:async';
import 'dart:convert';

// 2. Flutter imports
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 3. Third party packages
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

// 4. Local imports (relative paths)
import '../models/kullanici_model.dart';
import '../service/konum_servisi.dart';
import '../utils/yardimci_fonksiyonlar.dart';
```

### Sınıf Yapısı
```dart
class OrnekServis {
  // 1. Static variables
  static OrnekServis? _instance;
  
  // 2. Instance variables
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isInitialized = false;
  
  // 3. Constructor
  OrnekServis._();
  
  // 4. Factory constructor
  factory OrnekServis() => instance;
  
  // 5. Getters
  static OrnekServis get instance {
    _instance ??= OrnekServis._();
    return _instance!;
  }
  
  // 6. Public methods
  Future<void> servisiBaslat() async {
    try {
      // İş mantığı
      _isInitialized = true;
      print('✅ Servis başarıyla başlatıldı');
    } catch (e) {
      print('❌ Servis başlatma hatası: $e');
      rethrow;
    }
  }
  
  // 7. Private methods
  Future<void> _veriKaydet(Map<String, dynamic> veri) async {
    // Private iş mantığı
  }
}
```

---

## 🛡️ Hata Yönetimi

### Try-Catch Pattern
```dart
// ✅ Doğru - Detaylı hata yönetimi
Future<void> kullaniciKaydet(KullaniciModel kullanici) async {
  try {
    await _firestore
        .collection('kullanicilar')
        .doc(kullanici.id)
        .set(kullanici.toMap());
    
    print('✅ Kullanıcı başarıyla kaydedildi: ${kullanici.ad}');
  } on FirebaseException catch (e) {
    print('❌ Firebase hatası: ${e.message}');
    throw 'Kullanıcı kaydedilemedi: ${e.message}';
  } catch (e) {
    print('❌ Beklenmeyen hata: $e');
    throw 'Beklenmeyen bir hata oluştu';
  }
}
```

### Null Safety
```dart
// ✅ Doğru - Null safety kullanımı
String? kullaniciAdi = kullanici?.ad;
String guvenliAd = kullaniciAdi ?? 'Bilinmeyen Kullanıcı';

// Null check ile güvenli erişim
if (kullanici != null && kullanici.ad != null) {
  print('Kullanıcı adı: ${kullanici.ad}');
}
```

---

## 📱 UI/UX Kuralları

### Widget Yapısı
```dart
class KullaniciListesiWidget extends StatefulWidget {
  final String bolgeId;
  final Function(KullaniciModel) kullaniciSecildi;
  
  const KullaniciListesiWidget({
    super.key,
    required this.bolgeId,
    required this.kullaniciSecildi,
  });
  
  @override
  State<KullaniciListesiWidget> createState() => _KullaniciListesiWidgetState();
}

class _KullaniciListesiWidgetState extends State<KullaniciListesiWidget> {
  bool _yukleniyor = true;
  List<KullaniciModel> _kullanicilar = [];
  
  @override
  void initState() {
    super.initState();
    _kullanicilariYukle();
  }
  
  @override
  Widget build(BuildContext context) {
    if (_yukleniyor) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return ListView.builder(
      itemCount: _kullanicilar.length,
      itemBuilder: (context, index) {
        final kullanici = _kullanicilar[index];
        return KullaniciKartiWidget(
          kullanici: kullanici,
          onTap: () => widget.kullaniciSecildi(kullanici),
        );
      },
    );
  }
  
  Future<void> _kullanicilariYukle() async {
    try {
      setState(() => _yukleniyor = true);
      
      final snapshot = await FirebaseFirestore.instance
          .collection('kullanicilar')
          .where('bolgeId', isEqualTo: widget.bolgeId)
          .get();
      
      _kullanicilar = snapshot.docs
          .map((doc) => KullaniciModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ Kullanıcılar yüklenirken hata: $e');
      _hataMesajiGoster('Kullanıcılar yüklenemedi');
    } finally {
      setState(() => _yukleniyor = false);
    }
  }
  
  void _hataMesajiGoster(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mesaj),
        backgroundColor: Colors.red,
      ),
    );
  }
}
```

### Tema Kullanımı
```dart
// ✅ Doğru - Tema renklerini kullan
Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Theme.of(context).primaryColor,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(
    'Başlık',
    style: Theme.of(context).textTheme.headline6?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.bold,
    ),
  ),
)
```

---

## 🔄 State Management

### setState Kullanımı
```dart
// ✅ Doğru - Minimal setState
class _OrnekWidgetState extends State<OrnekWidget> {
  bool _yukleniyor = false;
  String? _hataMesaji;
  
  Future<void> _veriYukle() async {
    setState(() {
      _yukleniyor = true;
      _hataMesaji = null;
    });
    
    try {
      // Async işlem
      await _veriGetir();
    } catch (e) {
      setState(() {
        _hataMesaji = e.toString();
      });
    } finally {
      setState(() {
        _yukleniyor = false;
      });
    }
  }
}
```

### StreamSubscription Yönetimi
```dart
class _KonumTakipWidgetState extends State<KonumTakipWidget> {
  StreamSubscription<Position>? _konumSubscription;
  
  @override
  void initState() {
    super.initState();
    _konumTakibiniBaslat();
  }
  
  @override
  void dispose() {
    _konumSubscription?.cancel();
    super.dispose();
  }
  
  void _konumTakibiniBaslat() {
    _konumSubscription = Geolocator.getPositionStream().listen(
      (position) {
        setState(() {
          // Konum güncelleme
        });
      },
      onError: (error) {
        print('❌ Konum takip hatası: $error');
      },
    );
  }
}
```

---

## 🚀 Performance Kuralları

### const Kullanımı
```dart
// ✅ Doğru - const widget'lar
const SizedBox(height: 16);
const CircularProgressIndicator();
const Text('Başlık');

// ❌ Yanlış - Her build'de yeni widget
SizedBox(height: 16);
CircularProgressIndicator();
Text('Başlık');
```

### ListView Optimization
```dart
// ✅ Doğru - ListView.builder kullan
ListView.builder(
  itemCount: _kullanicilar.length,
  itemBuilder: (context, index) {
    return KullaniciKartiWidget(
      kullanici: _kullanicilar[index],
    );
  },
)

// ❌ Yanlış - Tüm listeyi build et
ListView(
  children: _kullanicilar.map((kullanici) {
    return KullaniciKartiWidget(kullanici: kullanici);
  }).toList(),
)
```

### Image Caching
```dart
// ✅ Doğru - CachedNetworkImage kullan
CachedNetworkImage(
  imageUrl: kullanici.profilResmiUrl ?? '',
  placeholder: (context, url) => const CircularProgressIndicator(),
  errorWidget: (context, url, error) => const Icon(Icons.person),
)
```

---

## 🔒 Güvenlik Kuralları

### API Key Yönetimi
```dart
// ✅ Doğru - Environment variables kullan
final apiKey = const String.fromEnvironment('GOOGLE_MAPS_API_KEY');

// ❌ Yanlış - Hardcoded API key
const String apiKey = "AIzaSyB1234567890";
```

### Input Validation
```dart
// ✅ Doğru - Input validation
String? emailDogrula(String email) {
  if (email.isEmpty) {
    return 'E-posta boş olamaz';
  }
  
  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
    return 'Geçerli bir e-posta adresi girin';
  }
  
  return null;
}
```

---

## 📊 Logging Kuralları

### Log Seviyeleri
```dart
// ✅ Doğru - Anlamlı log mesajları
print('✅ Kullanıcı başarıyla giriş yaptı: ${kullanici.email}');
print('❌ Giriş hatası: $hata');
print('📱 Uygulama başlatılıyor...');
print('🔄 Konum güncelleniyor...');
print('⚠️ İnternet bağlantısı zayıf');

// ❌ Yanlış - Anlamsız loglar
print('ok');
print('error');
print('test');
```

### Debug vs Release
```dart
// ✅ Doğru - Debug kontrolü
if (kDebugMode) {
  print('Debug: $mesaj');
}

// Production'da log'ları kapat
const bool enableLogging = bool.fromEnvironment('ENABLE_LOGGING', defaultValue: false);
if (enableLogging) {
  print('Log: $mesaj');
}
```

---

## 🧪 Test Kuralları

### Unit Test Örneği
```dart
// test/kullanici_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import '../lib/models/kullanici_model.dart';

void main() {
  group('KullaniciModel Tests', () {
    test('fromMap should create correct model', () {
      final data = {
        'name': 'Ahmet Yılmaz',
        'email': 'ahmet@example.com',
        'role': 'Yolcu',
      };
      
      final kullanici = KullaniciModel.fromMap(data, 'test-id');
      
      expect(kullanici.id, 'test-id');
      expect(kullanici.name, 'Ahmet Yılmaz');
      expect(kullanici.email, 'ahmet@example.com');
      expect(kullanici.role, 'Yolcu');
    });
    
    test('toMap should return correct data', () {
      final kullanici = KullaniciModel(
        id: 'test-id',
        name: 'Ahmet Yılmaz',
        email: 'ahmet@example.com',
        role: 'Yolcu',
      );
      
      final map = kullanici.toMap();
      
      expect(map['name'], 'Ahmet Yılmaz');
      expect(map['email'], 'ahmet@example.com');
      expect(map['role'], 'Yolcu');
    });
  });
}
```

---

## 📋 Checklist

### Her Yeni Özellik İçin
- [ ] Türkçe değişken isimleri kullanıldı
- [ ] Try-catch blokları eklendi
- [ ] Loading state'leri eklendi
- [ ] Error handling eklendi
- [ ] Log mesajları eklendi
- [ ] const widget'lar kullanıldı
- [ ] dispose metodları eklendi
- [ ] Input validation eklendi
- [ ] Unit test yazıldı

### Code Review Checklist
- [ ] Kod standartlarına uygun
- [ ] Performance optimize edildi
- [ ] Security kontrol edildi
- [ ] Error handling yeterli
- [ ] UI/UX kullanıcı dostu
- [ ] Documentation güncel
- [ ] Test coverage yeterli

---

## 🔄 Güncelleme Süreci

Bu kurallar sürekli güncellenmelidir:
1. Yeni Flutter versiyonları çıktığında
2. Best practices değiştiğinde
3. Team feedback'leri alındığında
4. Yeni güvenlik açıkları tespit edildiğinde

**Son Güncelleme**: 2024
**Versiyon**: 1.0
**Geliştirici**: Servis Takip Uygulaması Ekibi
