import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
class TopNotificationService {
  static OverlayEntry? _currentOverlay;
  static bool _isShowing = false;
  static void showSuccess({
    required BuildContext context,
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    _showNotification(
      context: context,
      message: message,
      icon: Icons.check_circle,
      iconColor: Colors.green,
      duration: duration,
    );
  }
  static void showError({
    required BuildContext context,
    required String message,
    Duration duration = const Duration(seconds: 4),
  }) {
    _showNotification(
      context: context,
      message: message,
      icon: Icons.error,
      iconColor: Colors.red,
      duration: duration,
    );
  }
  static void showInfo({
    required BuildContext context,
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    _showNotification(
      context: context,
      message: message,
      icon: Icons.info,
      iconColor: Colors.blue,
      duration: duration,
    );
  }
  static void showWarning({
    required BuildContext context,
    required String message,
    Duration duration = const Duration(seconds: 3),
  }) {
    _showNotification(
      context: context,
      message: message,
      icon: Icons.warning,
      iconColor: Colors.orange,
      duration: duration,
    );
  }
  static void showLocationStarted(BuildContext context) {
    showSuccess(
      context: context,
      message: 'Konum paylaşımı başlatıldı',
    );
  }
  static void showLocationStopped(BuildContext context) {
    showWarning(
      context: context,
      message: 'Konum paylaşımı durduruldu',
    );
  }
  static void _showNotification({
    required BuildContext context,
    required String message,
    required IconData icon,
    required Color iconColor,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (_isShowing) {
      _hideCurrentNotification();
    }
    _isShowing = true;
    HapticFeedback.lightImpact();
    final overlay = Overlay.of(context);
    _currentOverlay = OverlayEntry(
      builder: (context) => _TopNotificationWidget(
        message: message,
        icon: icon,
        iconColor: iconColor,
        onDismiss: _hideCurrentNotification,
      ),
    );
    overlay.insert(_currentOverlay!);
    Future.delayed(duration, () {
      _hideCurrentNotification();
    });
  }
  static void _hideCurrentNotification() {
    if (_currentOverlay != null && _isShowing) {
      _currentOverlay!.remove();
      _currentOverlay = null;
      _isShowing = false;
    }
  }
  static void clearAll() {
    _hideCurrentNotification();
  }
}
class _TopNotificationWidget extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onDismiss;
  const _TopNotificationWidget({
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.onDismiss,
  });
  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}
class _TopNotificationWidgetState extends State<_TopNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _opacityAnimation;
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    _animationController.forward();
  }
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  void _dismiss() async {
    await _animationController.reverse();
    widget.onDismiss();
  }
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _opacityAnimation,
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(16),
                    shadowColor: Colors.black.withOpacity(0.2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.grey.shade200,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: widget.iconColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              widget.icon,
                              color: widget.iconColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              widget.message,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _dismiss,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Updated

