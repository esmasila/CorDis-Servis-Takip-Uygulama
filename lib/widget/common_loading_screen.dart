import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
class CommonLoadingScreen extends StatelessWidget {
  final String? message;
  final String? subtitle;
  final bool showLogo;
  final bool showAppName;
  final double logoSize;
  final Duration animationDuration;
  const CommonLoadingScreen({
    super.key,
    this.message,
    this.subtitle,
    this.showLogo = true,
    this.showAppName = true,
    this.logoSize = 120,
    this.animationDuration = const Duration(milliseconds: 800),
  });
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
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showLogo) ...[
                  _buildAnimatedLogo(),
                  const SizedBox(height: 32),
                ],
                if (showAppName) ...[
                  _buildAppName(),
                  const SizedBox(height: 24),
                ],
                _buildLoadingIndicator(),
                if (message != null) ...[
                  const SizedBox(height: 24),
                  _buildMessage(),
                ],
                if (subtitle != null) ...[
                  const SizedBox(height: 16),
                  _buildSubtitle(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildAnimatedLogo() {
    return TweenAnimationBuilder<double>(
      duration: animationDuration,
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Container(
            width: logoSize,
            height: logoSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: AppColors.primaryGradient,
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
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: AppColors.secondaryGradient,
                    ),
                    child: Icon(
                      Icons.navigation_rounded,
                      size: logoSize * 0.4,
                      color: Colors.white,
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
  Widget _buildAppName() {
    return TweenAnimationBuilder<double>(
      duration: animationDuration,
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: Text(
              'CORDİS',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                fontSize: 28,
              ),
            ),
          ),
        );
      },
    );
  }
  Widget _buildLoadingIndicator() {
    return TweenAnimationBuilder<double>(
      duration: animationDuration,
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              backgroundColor: AppColors.primary.withOpacity(0.2),
            ),
          ),
        );
      },
    );
  }
  Widget _buildMessage() {
    return TweenAnimationBuilder<double>(
      duration: animationDuration,
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 15 * (1 - value)),
            child: Text(
              message!,
              style: TextStyle(
                fontSize: 18,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
  Widget _buildSubtitle() {
    return TweenAnimationBuilder<double>(
      duration: animationDuration,
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: Text(
              subtitle!,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
}
class SimpleLoadingIndicator extends StatelessWidget {
  final String? message;
  final double size;
  final Color? color;
  const SimpleLoadingIndicator({
    super.key,
    this.message,
    this.size = 24,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: size * 0.125,
            valueColor: AlwaysStoppedAnimation<Color>(
              color ?? AppColors.primary,
            ),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(
            message!,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
class FullScreenLoading extends StatelessWidget {
  final String? message;
  final String? subtitle;
  const FullScreenLoading({
    super.key,
    this.message,
    this.subtitle,
  });
  @override
  Widget build(BuildContext context) {
    return CommonLoadingScreen(
      message: message ?? 'Yükleniyor...',
      subtitle: subtitle ?? 'Lütfen bekleyin',
      showLogo: true,
      showAppName: true,
    );
  }
}





