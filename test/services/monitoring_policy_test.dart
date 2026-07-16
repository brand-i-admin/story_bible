import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/services/monitoring_policy.dart';

void main() {
  group('MonitoringPolicy', () {
    test('dev 환경에서는 릴리스 빌드여도 수집하지 않는다', () {
      final policy = MonitoringPolicy.resolve(
        runtimeEnvironment: 'dev',
        isReleaseMode: true,
        isWeb: false,
      );

      expect(policy.analyticsEnabled, isFalse);
      expect(policy.crashlyticsEnabled, isFalse);
    });

    test('real 릴리스에서는 Analytics와 Crashlytics를 수집한다', () {
      final policy = MonitoringPolicy.resolve(
        runtimeEnvironment: 'real',
        isReleaseMode: true,
        isWeb: false,
      );

      expect(policy.analyticsEnabled, isTrue);
      expect(policy.crashlyticsEnabled, isTrue);
    });

    test('prod 별칭도 운영 환경으로 취급한다', () {
      final policy = MonitoringPolicy.resolve(
        runtimeEnvironment: 'PROD',
        isReleaseMode: true,
        isWeb: false,
      );

      expect(policy.analyticsEnabled, isTrue);
      expect(policy.crashlyticsEnabled, isTrue);
    });

    test('real 디버그는 명시적 테스트 플래그가 없으면 수집하지 않는다', () {
      final policy = MonitoringPolicy.resolve(
        runtimeEnvironment: 'real',
        isReleaseMode: false,
        isWeb: false,
      );

      expect(policy.analyticsEnabled, isFalse);
      expect(policy.crashlyticsEnabled, isFalse);
    });

    test('명시적 테스트 플래그는 real 디버그 수집만 허용한다', () {
      final policy = MonitoringPolicy.resolve(
        runtimeEnvironment: 'real',
        isReleaseMode: false,
        isWeb: false,
        forceEnabled: true,
      );

      expect(policy.analyticsEnabled, isTrue);
      expect(policy.crashlyticsEnabled, isTrue);
    });

    test('명시적 테스트 플래그를 줘도 dev에서는 수집하지 않는다', () {
      final policy = MonitoringPolicy.resolve(
        runtimeEnvironment: 'dev',
        isReleaseMode: false,
        isWeb: false,
        forceEnabled: true,
      );

      expect(policy.analyticsEnabled, isFalse);
      expect(policy.crashlyticsEnabled, isFalse);
    });

    test('웹에서는 Analytics만 수집하고 Crashlytics는 호출하지 않는다', () {
      final policy = MonitoringPolicy.resolve(
        runtimeEnvironment: 'real',
        isReleaseMode: true,
        isWeb: true,
      );

      expect(policy.analyticsEnabled, isTrue);
      expect(policy.crashlyticsEnabled, isFalse);
    });
  });
}
