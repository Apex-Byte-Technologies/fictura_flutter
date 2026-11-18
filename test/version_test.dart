import 'dart:io';

import 'package:fictura_flutter/fictura_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version sent as x-fictura-wrapper is the pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(ficturaFlutterVersion, version);
  });

  test('the Android library version matches too', () {
    final gradle = File('android/build.gradle.kts').readAsStringSync();
    expect(
      RegExp(
        r'^version = "([^"]+)"',
        multiLine: true,
      ).firstMatch(gradle)!.group(1),
      ficturaFlutterVersion,
    );
  });
}
