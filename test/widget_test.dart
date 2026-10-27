import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_financial_manager/main.dart';

void main() {
  testWidgets('App starts and shows a loading indicator or login screen',
          (WidgetTester tester) async {
        await tester.pumpWidget(const MyApp());

        // Before Firebase's authStateChanges() stream emits, the app shows
        // a loading spinner (per the StreamBuilder in main.dart).
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });
}