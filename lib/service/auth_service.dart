import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Future<String?> signup({
    required String name,
    required String email,
    required String password,
    required String role,
    required String regionId,
  }) async {
    try {
      final uc = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      await _firestore.collection('users').doc(uc.user!.uid).set({
        'name': name.trim(),
        'email': email.trim(),
        'role': role,
        'regionId': regionId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!uc.user!.emailVerified) {
        await uc.user!.sendEmailVerification();
      }
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'Bu e‑posta zaten kullanımda.';
        case 'invalid-email':
          return 'Geçersiz e‑posta adresi.';
        case 'weak-password':
          return 'Şifre çok zayıf.';
        default:
          return e.message;
      }
    } catch (e) {
      return e.toString();
    }
  }
  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      if (email.trim().isEmpty || password.trim().isEmpty) {
        return 'E-posta ve şifre boş olamaz.';
      }
      print('🔐 Login attempt: Email=${email.trim()}');
      UserCredential userCredential;
      try {
        userCredential = await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password.trim(),
        );
        print('✅ Firebase Auth başarılı');
      } on FirebaseAuthException catch (e) {
        print('❌ Firebase Auth hatası: ${e.code} - ${e.message}');
        switch (e.code) {
          case 'user-not-found':
            return 'Bu e-posta adresi ile kayıtlı kullanıcı bulunamadı.';
          case 'wrong-password':
            return 'Şifre hatalı.';
          case 'invalid-email':
            return 'Geçersiz e-posta adresi.';
          case 'user-disabled':
            return 'Bu hesap devre dışı bırakılmış.';
          case 'too-many-requests':
            return 'Çok fazla başarısız deneme. Lütfen daha sonra tekrar deneyin.';
          case 'invalid-credential':
            return 'E-posta veya şifre hatalı. Lütfen bilgilerinizi kontrol edin.';
          case 'operation-not-allowed':
            return 'E-posta/şifre girişi etkinleştirilmemiş.';
          case 'weak-password':
            return 'Şifre çok zayıf.';
          default:
            return 'Giriş hatası (${e.code}): ${e.message}';
        }
      }
      final user = userCredential.user;
      if (user == null) {
        return 'Giriş işlemi başarısız.';
      }
      DocumentSnapshot userDoc;
      try {
        userDoc = await _firestore.collection('users').doc(user.uid).get();
      } catch (e) {
        return 'Veritabanı bağlantısında sorun oluştu.';
      }
      if (!userDoc.exists) {
        return 'Kullanıcı profili bulunamadı.';
      }
      final userData = userDoc.data() as Map<String, dynamic>?;
      if (userData == null) {
        return 'Kullanıcı verisi okunamadı.';
      }
      final userRole = userData['role'] as String?;
      if (userRole == null || userRole.isEmpty) {
        return 'Kullanıcı rol bilgisi eksik.';
      }
      final formattedRole = userRole[0].toUpperCase() + userRole.substring(1).toLowerCase();
      if (formattedRole == 'Admin') {
        return formattedRole;
      }
      bool isEmailVerified = false;
      try {
        await user.reload();
        final refreshedUser = _auth.currentUser;
        if (refreshedUser != null) {
          isEmailVerified = refreshedUser.emailVerified;
        }
      } catch (e) {
        isEmailVerified = false;
      }
      if (!isEmailVerified) {
        return 'E-posta adresinizi doğrulamanız gerekiyor. Lütfen e-posta kutunuzu kontrol edin.';
      }
      return formattedRole;
    } catch (e) {
      return 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.';
    }
  }
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  Future<String?> getCurrentUserRole() async {
    final u = _auth.currentUser;
    if (u == null) return null;
    final doc = await _firestore.collection('users').doc(u.uid).get();
    return doc.exists ? doc.get('role') as String : null;
  }
  Future<bool> refreshEmailVerified() async {
    final u = _auth.currentUser;
    if (u == null) return false;
    await u.reload();
    return u.emailVerified;
  }
  Future<void> resendEmailVerification() async {
    final u = _auth.currentUser;
    if (u != null && !u.emailVerified) {
      await u.sendEmailVerification();
    }
  }
  Future<void> signOut() => _auth.signOut();
}
