import 'character.dart';

class CharacterStudyProgress {
  const CharacterStudyProgress({
    required this.character,
    required this.completedCount,
    required this.totalCount,
  });

  final Character character;
  final int completedCount;
  final int totalCount;

  double get fraction {
    if (totalCount <= 0) {
      return 0;
    }
    return completedCount / totalCount;
  }
}
