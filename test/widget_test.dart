import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veille_ia/main.dart';

void main() {
  testWidgets('Veille IA démarre', (WidgetTester tester) async {
    await tester.pumpWidget(const VeilleIAApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}