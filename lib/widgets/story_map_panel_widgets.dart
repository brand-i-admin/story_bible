part of 'story_map_panel.dart';

class _NonGeographicRegionCard extends StatelessWidget {
  const _NonGeographicRegionCard({required this.regions});

  final List<Landmark> regions;

  @override
  Widget build(BuildContext context) {
    if (regions.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFBEF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFB89A66), width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '✨ 환상 / 비지리적',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF8C6743),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          for (final region in regions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(region.emoji, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      region.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3D2A14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CharacterColorLegend extends StatelessWidget {
  const _CharacterColorLegend({
    required this.codes,
    required this.colorForCharacter,
    required this.nameForCharacter,
  });

  final Set<String> codes;
  final Color Function(String characterCode) colorForCharacter;
  final String Function(String characterCode)? nameForCharacter;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xF2FFFBEF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB89A66), width: 0.9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 4,
            offset: Offset(0, 1.5),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 5,
        children: [
          for (final code in codes)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorForCharacter(code),
                    border: Border.all(color: Colors.white, width: 1.2),
                    boxShadow: const [
                      BoxShadow(color: Color(0x44000000), blurRadius: 1.5),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  nameForCharacter?.call(code) ?? code,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF3D2A14),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
