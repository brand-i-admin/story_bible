import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/widgets/proposal/approve_proposal_dialog.dart';

void main() {
  group('approve proposal position markers', () {
    test('null after_story_index 는 맨 앞 제안 위치로 해석한다', () {
      expect(normalizeSuggestedAfterStoryIndex(null), 0);
      expect(
        isSuggestedProposalPosition(
          candidateAfterStoryIndex: 0,
          proposedAfterStoryIndex: null,
        ),
        isTrue,
      );
    });

    test('제안자가 고른 after_story_index 만 제안 위치로 표시한다', () {
      expect(
        isSuggestedProposalPosition(
          candidateAfterStoryIndex: 3,
          proposedAfterStoryIndex: 3,
        ),
        isTrue,
      );
      expect(
        isSuggestedProposalPosition(
          candidateAfterStoryIndex: 4,
          proposedAfterStoryIndex: 3,
        ),
        isFalse,
      );
    });
  });
}
