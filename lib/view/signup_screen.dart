import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'login_screen.dart';
import '../widget/snackbar.dart';
import '../widget/common_loading_screen.dart';
import '../utils/app_colors.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  _SignupScreenState createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _selectedRegionId;
  bool _isLoading = false;
  bool _isPasswordHidden = true;
  bool _isPageLoading = true;
  List<Map<String, dynamic>> _regions = [];
  @override
  void initState() {
    super.initState();
    _loadRegions();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isPageLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _loadRegions() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('regions').get();
      setState(() {
        _regions = snapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  'name': doc['name'] as String,
                })
            .toList();
      });
    } catch (e) {
      showSnackBar(
        text: 'Bölgeler yüklenirken hata oluştu: $e',
        backgroundColor: AppColors.error,
      );
    }
  }

  void _signup() async {
    if (_nameController.text.trim().isEmpty) {
      showSnackBar(text: 'İsim boş olamaz', backgroundColor: AppColors.error);
      return;
    }
    if (_emailController.text.trim().isEmpty) {
      showSnackBar(
          text: 'E-posta boş olamaz', backgroundColor: AppColors.error);
      return;
    }
    if (_passwordController.text.trim().isEmpty) {
      showSnackBar(text: 'Şifre boş olamaz', backgroundColor: AppColors.error);
      return;
    }
    if (_selectedRegionId == null) {
      showSnackBar(
          text: 'Lütfen bir bölge seçin', backgroundColor: AppColors.error);
      return;
    }
    setState(() => _isLoading = true);
    try {
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      await userCredential.user!.sendEmailVerification();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'role': 'Yolcu',
        'regionId': _selectedRegionId,
        'createdAt': FieldValue.serverTimestamp(),
        'isEmailVerified': false,
      });

      await FirebaseFirestore.instance
          .collection('passengers')
          .doc(userCredential.user!.uid)
          .set({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'role': 'Yolcu',
        'regionId': _selectedRegionId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        showSnackBar(
          text: 'Hesap başarıyla oluşturuldu! E-posta onayı gönderildi.',
          backgroundColor: AppColors.success,
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Kayıt hatası oluştu';
      if (e.code == 'weak-password') {
        errorMessage = 'Şifre çok zayıf';
      } else if (e.code == 'email-already-in-use') {
        errorMessage = 'Bu e-posta adresi zaten kullanılıyor';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'Geçersiz e-posta adresi';
      }
      if (mounted) {
        showSnackBar(
          text: errorMessage,
          backgroundColor: AppColors.error,
        );
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(
          text: 'Beklenmeyen hata: $e',
          backgroundColor: AppColors.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.background,
                  AppColors.surfaceVariant,
                  Color(0xFFE8F4FD),
                  Color(0xFFF0F9FF),
                ],
                stops: [0.0, 0.3, 0.7, 1.0],
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(height: screenHeight * 0.04),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeOutBack,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.elasticOut,
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Image.asset(
                                'assets/cordis_logo_new2.jpg',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Hesap Oluştur',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.cardBorder.withOpacity(0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.shadowMedium,
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.05),
                            blurRadius: 40,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Yeni Hesap',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Bilgilerinizi girerek hesap oluşturun',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: AppColors.surfaceVariant,
                            ),
                            child: TextField(
                              controller: _nameController,
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Ad Soyad',
                                labelStyle: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: Icon(
                                  Icons.person_outlined,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: AppColors.surfaceVariant,
                            ),
                            child: TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                labelText: 'E-posta Adresi',
                                labelStyle: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: Icon(
                                  Icons.email_outlined,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: AppColors.surfaceVariant,
                            ),
                            child: TextField(
                              controller: _passwordController,
                              obscureText: _isPasswordHidden,
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Şifre',
                                labelStyle: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: Icon(
                                  Icons.lock_outlined,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isPasswordHidden
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: AppColors.textSecondary,
                                    size: 22,
                                  ),
                                  onPressed: () {
                                    setState(() =>
                                        _isPasswordHidden = !_isPasswordHidden);
                                  },
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: AppColors.surfaceVariant,
                            ),
                            child: DropdownButtonFormField<String>(
                              value: _selectedRegionId,
                              decoration: InputDecoration(
                                labelText: 'Bölge Seçin',
                                labelStyle: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: Icon(
                                  Icons.location_on_outlined,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 18,
                                ),
                              ),
                              items: _regions.map((region) {
                                return DropdownMenuItem<String>(
                                  value: region['id'],
                                  child: Text(
                                    region['name'],
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 16,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedRegionId = value;
                                });
                              },
                              dropdownColor: Colors.white,
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: AppColors.primaryGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _signup,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Text(
                                      'Hesap Oluştur',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    Container(
                      margin: const EdgeInsets.only(bottom: 32),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Zaten hesabınız var mı? ',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const LoginScreen(),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                            ),
                            child: Text(
                              'Giriş Yap',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isPageLoading)
            Container(
              color: AppColors.background.withOpacity(0.9),
              child: const Center(
                child: CommonLoadingScreen(
                  message: 'Servis Takip',
                  subtitle: 'Yükleniyor...',
                  showLogo: true,
                  showAppName: false,
                  logoSize: 80,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Updated


// Updated Again

