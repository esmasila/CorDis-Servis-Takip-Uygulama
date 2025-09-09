import 'package:flutter/material.dart';
import '../service/auth_service.dart';
import 'login_screen.dart';
import '../widget/snackbar.dart';
final AuthService _authService = AuthService();
class SoforScreen extends StatelessWidget {
  const SoforScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(
        title: const Text('Şoför Ekranı'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _buildContent(context, role: 'Şoför', color: Colors.blue),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showSnackBar(text: 'Henüz tanımlanmadı.');
        },
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add),
      ),
    );
  }
}
class YolcuScreen extends StatelessWidget {
  const YolcuScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(
        title: const Text('Yolcu Ekranı'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _buildContent(context, role: 'Yolcu', color: Colors.green),
    );
  }
}
Widget _buildContent(
  BuildContext context, {
  required String role,
  required Color color,
}) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$role sayfasına hoş geldiniz!',
          style: TextStyle(
            fontSize: 18,
            color: Colors.grey.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),
        Builder(
          builder: (context) => ElevatedButton.icon(
            onPressed: () async {
              await _authService.signOut();
              showSnackBar(
                text: 'Başarıyla çıkış yapıldı.',
                backgroundColor: Colors.green.shade600,
              );
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Çıkış Yap'),
          ),
        ),
      ],
    ),
  );
}

// Updated


// Updated Again

