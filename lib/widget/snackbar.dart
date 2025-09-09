import 'package:flutter/material.dart';
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();
void showSnackBar({
  required String text,
  Duration duration = const Duration(seconds: 3),
  String? actionLabel,
  VoidCallback? onAction,
  Color backgroundColor = const Color(0xFF222222),
  Color textColor = Colors.white,
  Color actionTextColor = Colors.yellow,
}) {
  final snackBar = SnackBar(
    content: Text(text, style: TextStyle(color: textColor)),
    duration: duration,
    backgroundColor: backgroundColor,
    action: (actionLabel != null && onAction != null)
        ? SnackBarAction(
            label: actionLabel,
            onPressed: onAction,
            textColor: actionTextColor,
          )
        : null,
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final m = messengerKey.currentState;
    if (m == null) return;
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  });
}





