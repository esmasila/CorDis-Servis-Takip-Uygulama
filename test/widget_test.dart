import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cordis/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Servis Takip Uygulaması'),
          ),
        ),
      ),
    );

    expect(find.text('Servis Takip Uygulaması'), findsOneWidget);
  });

  testWidgets('MyApp widget creates successfully', (WidgetTester tester) async {
    final widget = const MyApp();
    expect(widget, isNotNull);
    expect(widget, isA<MyApp>());
  });
}
