import 'person.dart';

class PersonStudyProgress {
  const PersonStudyProgress({
    required this.person,
    required this.completedCount,
    required this.totalCount,
  });

  final Person person;
  final int completedCount;
  final int totalCount;

  double get fraction {
    if (totalCount <= 0) {
      return 0;
    }
    return completedCount / totalCount;
  }
}
