# 🔐 Güvenlik Kurulumu - API Anahtarları

Bu dosya, API anahtarlarınızı güvenli bir şekilde yönetmek için gerekli adımları açıklar.

## 🚨 Önemli Güvenlik Uyarısı

**API anahtarlarınız artık kodda sabit olarak bulunmuyor!** Bu değişiklikler sayesinde:
- API anahtarlarınız GitHub'da görünmez
- Her ortam için farklı anahtarlar kullanabilirsiniz
- Güvenlik riskleri minimize edilir

## 📋 Kurulum Adımları

### 1. Environment Dosyası Oluşturun

Proje kök dizininde `.env` dosyası oluşturun:

```bash
# Google Maps API Key
GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here

# Firebase Configuration
FIREBASE_API_KEY_WEB=your_firebase_web_api_key_here
FIREBASE_API_KEY_ANDROID=your_firebase_android_api_key_here
FIREBASE_API_KEY_IOS=your_firebase_ios_api_key_here
FIREBASE_PROJECT_ID=your_firebase_project_id_here
FIREBASE_MESSAGING_SENDER_ID=your_firebase_messaging_sender_id_here
FIREBASE_STORAGE_BUCKET=your_firebase_storage_bucket_here
FIREBASE_AUTH_DOMAIN=your_firebase_auth_domain_here
FIREBASE_MEASUREMENT_ID=your_firebase_measurement_id_here
```

### 2. Gerçek API Anahtarlarınızı Ekleyin

`.env` dosyasındaki placeholder değerleri gerçek API anahtarlarınızla değiştirin.

### 3. Dependencies Yükleyin

```bash
flutter pub get
```

### 4. Firebase Dosyalarını Güvenli Hale Getirin

Aşağıdaki dosyalar artık `.gitignore` tarafından hariç tutuluyor:
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `.env` ve tüm `.env.*` dosyaları

### 5. Build İşlemi

#### Android için:
```bash
flutter build apk --release
```

#### iOS için:
```bash
flutter build ios --release
```

## 🔧 Geliştirme Ortamı

Geliştirme sırasında `.env` dosyası otomatik olarak yüklenir. Uygulama başlatıldığında `ConfigService.initialize()` çağrılır.

## 🚀 Production Ortamı

Production ortamında API anahtarlarınızı şu şekillerde sağlayabilirsiniz:

### CI/CD Pipeline
- GitHub Actions, GitLab CI, vb. ortamlarda environment variables olarak tanımlayın
- Build sırasında `.env` dosyasını oluşturun

### Hosting Platformları
- Firebase Hosting, Vercel, Netlify gibi platformlarda environment variables kullanın

## 📱 Platform Özel Ayarlar

### Android
`android/app/src/main/AndroidManifest.xml` dosyasında API key placeholder kullanılıyor:
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="${GOOGLE_MAPS_API_KEY}" />
```

### iOS
`ios/Runner/AppDelegate.swift` dosyasında API key yorumlanmış durumda:
```swift
// Google Maps iOS API Key - will be loaded from environment variables
GMSServices.provideAPIKey("AIzaSyC628CANMpJ_YjsKGg4ASzAvESQ2f3MJGQ")
```

### Web
`web/index.html` dosyasında API key placeholder kullanılıyor:
```html
<script>
  window.GOOGLE_MAPS_API_KEY = 'AIzaSyC628CANMpJ_YjsKGg4ASzAvESQ2f3MJGQ';
</script>
```

## 🔍 Doğrulama

API anahtarlarınızın doğru yüklendiğini kontrol etmek için:

1. Uygulamayı çalıştırın
2. Console loglarında "✅ Konfigürasyon servisi başlatıldı" mesajını görün
3. Google Maps özelliklerinin çalıştığını test edin

## ⚠️ Güvenlik Notları

1. **Asla** `.env` dosyasını git'e commit etmeyin
2. **Asla** API anahtarlarını kod içinde sabit olarak yazmayın
3. Production ortamında farklı API anahtarları kullanın
4. API anahtarlarınızı düzenli olarak yenileyin
5. Kullanılmayan API anahtarlarını iptal edin

## 🆘 Sorun Giderme

### "API key not found" Hatası
- `.env` dosyasının proje kök dizininde olduğundan emin olun
- API anahtarının doğru yazıldığından emin olun
- `flutter pub get` komutunu çalıştırın

### Google Maps Çalışmıyor
- API anahtarının Google Cloud Console'da aktif olduğundan emin olun
- Gerekli API'lerin etkinleştirildiğinden emin olun (Maps JavaScript API, Directions API, vb.)

## 📞 Destek

Sorunlarınız için:
1. Bu dokümantasyonu kontrol edin
2. Console loglarını inceleyin
3. API anahtarlarınızın geçerliliğini kontrol edin
