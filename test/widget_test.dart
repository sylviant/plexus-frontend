import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexus/main.dart';

void main() {
  testWidgets('Counter infiltration test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PlexusApp());

    // Verify that our app starts (on login or home)
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
