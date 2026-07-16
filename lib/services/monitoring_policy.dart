class MonitoringPolicy {
  const MonitoringPolicy({
    required this.analyticsEnabled,
    required this.crashlyticsEnabled,
  });

  factory MonitoringPolicy.resolve({
    required String runtimeEnvironment,
    required bool isReleaseMode,
    required bool isWeb,
    bool forceEnabled = false,
  }) {
    final normalizedEnvironment = runtimeEnvironment.trim().toLowerCase();
    final isProductionEnvironment =
        normalizedEnvironment == 'real' || normalizedEnvironment == 'prod';
    final collectionEnabled =
        isProductionEnvironment && (isReleaseMode || forceEnabled);

    return MonitoringPolicy(
      analyticsEnabled: collectionEnabled,
      crashlyticsEnabled: collectionEnabled && !isWeb,
    );
  }

  final bool analyticsEnabled;
  final bool crashlyticsEnabled;
}
