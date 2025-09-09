import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class AvatarMarkerService {
  static final Map<String, BitmapDescriptor> _markerCache = {};
  static Future<BitmapDescriptor> createAvatarMarker({
    required String? profileImageUrl,
    required int stopNumber,
    required double size,
    bool isCompleted = false,
  }) async {
    final cacheKey =
        '${profileImageUrl ?? 'default'}_${stopNumber}_$size${isCompleted ? '_completed' : ''}';
    if (_markerCache.containsKey(cacheKey)) {
      return _markerCache[cacheKey]!;
    }
    try {
      final marker = await _generateAvatarMarker(
        profileImageUrl: profileImageUrl,
        stopNumber: stopNumber,
        size: size,
        isCompleted: isCompleted,
      );
      _markerCache[cacheKey] = marker;
      return marker;
    } catch (e) {
      print('Avatar marker oluşturma hatası: $e');
      return await _createDefaultMarker(stopNumber, size);
    }
  }

  static Future<BitmapDescriptor> _generateAvatarMarker({
    required String? profileImageUrl,
    required int stopNumber,
    required double size,
    required bool isCompleted,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final markerSize = size;
    final avatarPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = isCompleted ? Colors.green : Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    final avatarRadius = markerSize * 0.35;
    final avatarCenter = Offset(markerSize / 2, markerSize * 0.4);
    canvas.drawCircle(avatarCenter, avatarRadius, avatarPaint);
    canvas.drawCircle(avatarCenter, avatarRadius, borderPaint);
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      print('🔄 Profil fotoğrafı yükleniyor: $profileImageUrl');
      try {
        final imageData = await _loadImageFromUrl(profileImageUrl);
        if (imageData != null) {
          final codec = await ui.instantiateImageCodec(
            imageData,
            targetWidth: (avatarRadius * 2).toInt(),
            targetHeight: (avatarRadius * 2).toInt(),
          );
          final frame = await codec.getNextFrame();
          final clipPath = Path()
            ..addOval(Rect.fromCircle(
              center: avatarCenter,
              radius: avatarRadius - 2,
            ));
          canvas.save();
          canvas.clipPath(clipPath);
          final imageRect = Rect.fromCircle(
            center: avatarCenter,
            radius: avatarRadius - 2,
          );
          canvas.drawImageRect(
            frame.image,
            Rect.fromLTWH(0, 0, frame.image.width.toDouble(),
                frame.image.height.toDouble()),
            imageRect,
            Paint(),
          );
          canvas.restore();
        } else {
          await _drawDefaultAvatar(canvas, avatarCenter, avatarRadius - 2);
        }
      } catch (e) {
        print('Profil fotoğrafı yükleme hatası: $e');
        await _drawDefaultAvatar(canvas, avatarCenter, avatarRadius - 2);
      }
    } else {
      await _drawDefaultAvatar(canvas, avatarCenter, avatarRadius - 2);
    }
    final numberCircleRadius = markerSize * 0.15;
    final numberCenter = Offset(markerSize / 2, markerSize * 0.8);
    final numberCirclePaint = Paint()
      ..color = isCompleted ? Colors.green : Colors.red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(numberCenter, numberCircleRadius, numberCirclePaint);
    final textPainter = TextPainter(
      text: TextSpan(
        text: stopNumber.toString(),
        style: TextStyle(
          color: Colors.white,
          fontSize: markerSize * 0.12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        numberCenter.dx - textPainter.width / 2,
        numberCenter.dy - textPainter.height / 2,
      ),
    );
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawCircle(
      Offset(avatarCenter.dx + 2, avatarCenter.dy + 2),
      avatarRadius,
      shadowPaint,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(markerSize.toInt(), markerSize.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  static Future<Uint8List?> _loadImageFromUrl(String url) async {
    print('🔄 HTTP isteği yapılıyor: $url');
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      print('📡 HTTP yanıtı: ${response.statusCode}');
      if (response.statusCode == 200) {
        print(
            '✅ Resim başarıyla yüklendi, boyut: ${response.bodyBytes.length} bytes');
        return response.bodyBytes;
      } else {
        print('❌ HTTP hata kodu: ${response.statusCode}');
        print('   - Response body: ${response.body}');
      }
    } catch (e) {
      print('Resim yükleme hatası: $e');
    }
    return null;
  }

  static Future<void> _drawDefaultAvatar(
    Canvas canvas,
    Offset center,
    double radius,
  ) async {
    final gradient = RadialGradient(
      colors: [Colors.blue.shade300, Colors.blue.shade600],
    );
    final iconPaint = Paint()
      ..shader = gradient.createShader(Rect.fromCircle(
        center: center,
        radius: radius,
      ))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, iconPaint);
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.8, innerPaint);
    final personPaint = Paint()
      ..color = Colors.blue.shade600
      ..style = PaintingStyle.fill;
    final headRadius = radius * 0.25;
    final headCenter = Offset(center.dx, center.dy - radius * 0.15);
    canvas.drawCircle(headCenter, headRadius, personPaint);
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + radius * 0.25),
        width: radius * 0.6,
        height: radius * 0.5,
      ),
      Radius.circular(radius * 0.2),
    );
    canvas.drawRRect(bodyRect, personPaint);
  }

  static Future<BitmapDescriptor> _createDefaultMarker(
    int stopNumber,
    double size,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;
    final center = Offset(size / 2, size / 2);
    canvas.drawCircle(center, size / 2, paint);
    final textPainter = TextPainter(
      text: TextSpan(
        text: stopNumber.toString(),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.3,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  static Future<BitmapDescriptor> createCarMarker({
    required double size,
    required double heading,
    Color color = Colors.blue,
  }) async {
    final cacheKey = 'car_${size}_${heading}_${color.value}';
    if (_markerCache.containsKey(cacheKey)) {
      return _markerCache[cacheKey]!;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.save();
    canvas.translate(size / 2, size / 2);
    canvas.rotate(heading * (3.14159 / 180));
    canvas.translate(-size / 2, -size / 2);
    final carPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final carRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size / 2, size / 2),
        width: size * 0.6,
        height: size * 0.8,
      ),
      Radius.circular(size * 0.1),
    );
    canvas.drawRRect(carRect, carPaint);
    canvas.drawRRect(carRect, borderPaint);
    final arrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final arrowPath = Path();
    final arrowSize = size * 0.2;
    final arrowCenter = Offset(size / 2, size * 0.3);
    arrowPath.moveTo(arrowCenter.dx, arrowCenter.dy - arrowSize);
    arrowPath.lineTo(arrowCenter.dx - arrowSize / 2, arrowCenter.dy);
    arrowPath.lineTo(arrowCenter.dx + arrowSize / 2, arrowCenter.dy);
    arrowPath.close();
    canvas.drawPath(arrowPath, arrowPaint);
    canvas.restore();
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final marker = BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    _markerCache[cacheKey] = marker;
    return marker;
  }

  static void clearCache() {
    _markerCache.clear();
  }

  static void removeCacheItem(String key) {
    _markerCache.remove(key);
  }

  static Future<BitmapDescriptor> createEmojiMarker({
    String emoji = '🚌',
    double size = 80.0,
    Color backgroundColor = const Color(0xFF2563EB),
    Color borderColor = const Color(0xFFFFFFFF),
    double borderWidth = 3.0,
  }) async {
    final cacheKey =
        'emoji_${emoji}_${size}_${backgroundColor.value}_${borderColor.value}_${borderWidth}';
    if (_markerCache.containsKey(cacheKey)) {
      return _markerCache[cacheKey]!;
    }
    try {
      final int canvasSize = size.toInt();
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final double radius = canvasSize / 2.0;
      final Offset center = Offset(radius, radius);

      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: emoji,
          style: TextStyle(
            fontSize: canvasSize * 0.8,
            color: Colors.black,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      final Offset emojiOffset = Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      );
      textPainter.paint(canvas, emojiOffset);

      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(canvasSize, canvasSize);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final Uint8List bytes = byteData.buffer.asUint8List();
        final marker = BitmapDescriptor.fromBytes(bytes);
        _markerCache[cacheKey] = marker;
        return marker;
      }
    } catch (e) {
      debugPrint('Emoji marker oluşturma hatası: $e');
    }
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
  }
}



 Again


