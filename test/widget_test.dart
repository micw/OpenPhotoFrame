// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:open_photo_frame/main.dart';
import 'package:open_photo_frame/infrastructure/services/json_config_service.dart';

void main() {
  testWidgets('App initializes without crashing', (WidgetTester tester) async {
    // Create a mock config service for testing
    final configService = JsonConfigService();
    
    // Build our app and trigger a frame.
    await tester.pumpWidget(OpenPhotoFrameApp(configProvider: configService));
    
    // If we get here without throwing, the app initialized successfully
    expect(find.byType(OpenPhotoFrameApp), findsOneWidget);
  });
}
