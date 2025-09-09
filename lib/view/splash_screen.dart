import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/auth');
    });
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: _BrandBlock(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _BrandBlock extends StatelessWidget {
  const _BrandBlock();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _assetExists(context, 'assets/cordis_logo_new.png'),
      builder: (context, snapPng) {
        final double s = _preferredSplashIconSize(context);
        if (snapPng.connectionState == ConnectionState.done &&
            (snapPng.data == true)) {
          return _buildLogo('assets/cordis_logo_new.png', s);
        }
        return FutureBuilder<bool>(
          future: _assetExists(context, 'assets/cordis_logo_new.jpg'),
          builder: (context, snapJpg) {
            if (snapJpg.connectionState == ConnectionState.done &&
                (snapJpg.data == true)) {
              return _buildLogo('assets/cordis_logo_new.jpg', s);
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _LogoOrPin(),
                const SizedBox(height: 16),
                Text(
                  'CORDİS',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    shadows: [
                      Shadow(
                        color: AppColors.primary.withOpacity(0.15),
                        offset: const Offset(0, 2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
  Future<bool> _assetExists(BuildContext context, String path) async {
    try {
      await DefaultAssetBundle.of(context).load(path);
      return true;
    } catch (_) {
      return false;
    }
  }
  double _preferredSplashIconSize(BuildContext context) {
    final double shortestSide = MediaQuery.of(context).size.shortestSide;
    final double calculated = shortestSide * 0.75;
    return calculated.clamp(280.0, 400.0).toDouble();
  }
  Widget _buildLogo(String path, double size) {
    return Container(
      width: size * 1.2,
      height: size * 1.2,
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 176, 176, 176),
        borderRadius: BorderRadius.circular(size * 0.1),
      ),
      child: Image.asset(
        path,
        fit: BoxFit.contain,
        color: null,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}
class _CordisPin extends StatelessWidget {
  final double size;
  const _CordisPin({this.size = 140});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(48),
        gradient: AppColors.secondaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.2),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.show_chart_rounded,
          size: size * 0.46,
          color: Colors.white,
        ),
      ),
    );
  }
}
class _LogoOrPin extends StatelessWidget {
  const _LogoOrPin();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _assetExists(context, 'assets/cordis_logo_new2.png'),
      builder: (context, snap) {
        final double s = _preferredSplashIconSize(context);
        if (snap.connectionState == ConnectionState.done) {
          if (snap.data == true) {
            return _buildLogo('assets/cordis_logo_new2.png', s);
          }
          return FutureBuilder<bool>(
            future: _assetExists(context, 'assets/cordis_logo_new2.jpg'),
            builder: (context, jpgSnap) {
              if (jpgSnap.hasData && jpgSnap.data == true) {
                return _buildLogo('assets/cordis_logo_new2.jpg', s);
              }
              return _CordisPin(size: s);
            },
          );
        }
        return SizedBox(
          width: s,
          height: s,
          child: CircularProgressIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.primary.withOpacity(0.2),
          ),
        );
      },
    );
  }
  Future<bool> _assetExists(BuildContext context, String path) async {
    try {
      await DefaultAssetBundle.of(context).load(path);
      return true;
    } catch (_) {
      return false;
    }
  }
  double _preferredSplashIconSize(BuildContext context) {
    final double shortestSide = MediaQuery.of(context).size.shortestSide;
    final double calculated = shortestSide * 0.75;
    return calculated.clamp(280.0, 400.0).toDouble();
  }
  Widget _buildLogo(String path, double size) {
    return Container(
      width: size * 1.2,
      height: size * 1.2,
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 183, 183, 183),
        borderRadius: BorderRadius.circular(size * 0.1),
      ),
      child: Image.asset(
        path,
        fit: BoxFit.contain,
        color: null,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}



 Again


