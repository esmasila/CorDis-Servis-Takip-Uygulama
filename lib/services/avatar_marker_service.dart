import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
class AvatarMarkerService {
  static const double _defaultSize = 60.0;
  static const Color _defaultBackgroundColor = Colors.blue;
  static const Color _textColor = Colors.white;
  static Future<BitmapDescriptor> createAvatarMarker({
    String? profileImageUrl,
    required int stopNumber,
    double size = _defaultSize,
    Color backgroundColor = _defaultBackgroundColor,
  }) async {
    try {
      final int canvasSize = size.toInt();
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final Paint backgroundPaint = Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.fill;
      final Paint borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      final double radius = canvasSize / 2.0;
      final Offset center = Offset(radius, radius);
      canvas.drawCircle(center, radius - 2, backgroundPaint);
      canvas.drawCircle(center, radius - 2, borderPaint);
      if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
        try {
          final ui.Image? profileImage =
              await _loadImageFromUrl(profileImageUrl);
          if (profileImage != null) {
            final double imageRadius = radius - 8;
            final Rect imageRect = Rect.fromCircle(
              center: center,
              radius: imageRadius,
            );
            final Path clipPath = Path()..addOval(imageRect);
            canvas.clipPath(clipPath);
            final Rect srcRect = Rect.fromLTWH(
              0,
              0,
              profileImage.width.toDouble(),
              profileImage.height.toDouble(),
            );
            canvas.drawImageRect(profileImage, srcRect, imageRect, Paint());
            canvas.restore();
            canvas.save();
          }
        } catch (e) {
          debugPrint('Profil fotoğrafı yükleme hatası: $e');
          _drawDefaultAvatar(canvas, center, radius - 8);
        }
      } else {
        _drawDefaultAvatar(canvas, center, radius - 8);
      }
      _drawStopNumber(canvas, stopNumber, canvasSize);
      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(canvasSize, canvasSize);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final Uint8List uint8List = byteData.buffer.asUint8List();
        return BitmapDescriptor.fromBytes(uint8List);
      }
    } catch (e) {
      debugPrint('Avatar marker oluşturma hatası: $e');
    }
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
  }
  static Future<ui.Image?> _loadImageFromUrl(String url) async {
    try {
      final http.Response response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final Uint8List bytes = response.bodyBytes;
        final ui.Codec codec = await ui.instantiateImageCodec(bytes);
        final ui.FrameInfo frameInfo = await codec.getNextFrame();
        return frameInfo.image;
      }
    } catch (e) {
      debugPrint('URL\'den resim yükleme hatası: $e');
    }
    return null;
  }
  static void _drawDefaultAvatar(Canvas canvas, Offset center, double radius) {
    final Paint avatarPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    final double headRadius = radius * 0.3;
    final Offset headCenter = Offset(center.dx, center.dy - radius * 0.2);
    canvas.drawCircle(headCenter, headRadius, avatarPaint);
    final double bodyRadius = radius * 0.5;
    final Offset bodyCenter = Offset(center.dx, center.dy + radius * 0.3);
    canvas.drawCircle(bodyCenter, bodyRadius, avatarPaint);
  }
  static void _drawStopNumber(Canvas canvas, int stopNumber, int canvasSize) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: stopNumber.toString(),
        style: TextStyle(
          color: _textColor,
          fontSize: canvasSize * 0.2,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final Offset textOffset = Offset(
      (canvasSize - textPainter.width) / 2,
      canvasSize * 0.75,
    );
    final Paint numberBackgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;
    final double numberRadius = textPainter.width / 2 + 4;
    final Offset numberCenter = Offset(
      textOffset.dx + textPainter.width / 2,
      textOffset.dy + textPainter.height / 2,
    );
    canvas.drawCircle(numberCenter, numberRadius, numberBackgroundPaint);
    textPainter.paint(canvas, textOffset);
  }
  static Future<BitmapDescriptor> createCarIcon({
    double size = 40.0,
    Color color = Colors.red,
  }) async {
    try {
      final int canvasSize = size.toInt();
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final Paint carPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final Paint borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      final Rect carRect = Rect.fromLTWH(
        canvasSize * 0.1,
        canvasSize * 0.3,
        canvasSize * 0.8,
        canvasSize * 0.4,
      );
      final RRect roundedCarRect = RRect.fromRectAndRadius(
        carRect,
        Radius.circular(canvasSize * 0.1),
      );
      canvas.drawRRect(roundedCarRect, carPaint);
      canvas.drawRRect(roundedCarRect, borderPaint);
      final Paint wheelPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;
      final double wheelRadius = canvasSize * 0.08;
      canvas.drawCircle(
        Offset(canvasSize * 0.25, carRect.bottom),
        wheelRadius,
        wheelPaint,
      );
      canvas.drawCircle(
        Offset(canvasSize * 0.75, carRect.bottom),
        wheelRadius,
        wheelPaint,
      );
      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(canvasSize, canvasSize);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final Uint8List uint8List = byteData.buffer.asUint8List();
        return BitmapDescriptor.fromBytes(uint8List);
      }
    } catch (e) {
      debugPrint('Araba ikonu oluşturma hatası: $e');
    }
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
  }
}





