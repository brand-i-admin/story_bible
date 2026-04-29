import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/models/event_proposal.dart';

void main() {
  group('QuizDraft', () {
    test('유효한 4지선다는 isValid=true', () {
      const q = QuizDraft(
        question: '요셉이 애굽으로 팔려간 이유는?',
        choices: ['질투', '기근', '전쟁', '순례'],
        answerIndex: 0,
        explanation: '창세기 37:28 형들이 요셉을 팔았다.',
      );
      expect(q.isValid, isTrue);
    });

    test('선택지 개수가 4가 아니면 invalid', () {
      const q = QuizDraft(
        question: 'Q',
        choices: ['a', 'b', 'c'], // 3개
        answerIndex: 0,
        explanation: 'exp',
      );
      expect(q.isValid, isFalse);
    });

    test('선택지 중 빈 문자열이 있으면 invalid', () {
      const q = QuizDraft(
        question: 'Q',
        choices: ['a', '', 'c', 'd'],
        answerIndex: 0,
        explanation: 'exp',
      );
      expect(q.isValid, isFalse);
    });

    test('answer_index 범위를 벗어나면 invalid', () {
      const q = QuizDraft(
        question: 'Q',
        choices: ['a', 'b', 'c', 'd'],
        answerIndex: 4,
        explanation: 'exp',
      );
      expect(q.isValid, isFalse);
    });

    test('해설이 비면 invalid', () {
      const q = QuizDraft(
        question: 'Q',
        choices: ['a', 'b', 'c', 'd'],
        answerIndex: 1,
        explanation: '   ',
      );
      expect(q.isValid, isFalse);
    });

    test('fromMap / toMap 왕복', () {
      final map = <String, dynamic>{
        'question': '문제',
        'choices': ['a', 'b', 'c', 'd'],
        'answer_index': 2,
        'explanation': '해설',
      };
      final q = QuizDraft.fromMap(map);
      expect(q.question, '문제');
      expect(q.choices, ['a', 'b', 'c', 'd']);
      expect(q.answerIndex, 2);
      expect(q.explanation, '해설');
      expect(q.toMap(), map);
    });
  });

  group('EventProposal.fromMap', () {
    Map<String, dynamic> baseRow() => {
      'id': 'prop-1',
      'proposer_user_id': 'u-1',
      'era_id': 'era-1',
      'title': '요셉 이야기',
      'summary': '요약',
      'character_codes': ['joseph'],
      'place_name': '애굽',
      'lat': 30.0,
      'lng': 31.0,
      'start_year': -1800,
      'end_year': -1700,
      'time_precision': 'approx',
      'bible_refs': [],
      'story_scenes': ['scene-1'],
      'scene_characters': [
        ['joseph'],
      ],
      'scene_image_paths': ['proposal-scenes/u-1/d/scene_1.png'],
      'scene_image_prompts': ['prompt'],
      'proposed_characters': [],
      'quiz_questions': [],
      'after_story_index': 0,
      'status': 'pending',
      'reviewed_by_user_id': null,
      'reviewed_at': null,
      'review_note': null,
      'approved_event_id': null,
      'created_at': '2026-04-22T00:00:00Z',
      'updated_at': '2026-04-22T00:00:00Z',
    };

    test('proposal_type 기본값은 new', () {
      final row = baseRow()..remove('proposal_type');
      row['quiz_questions'] = [
        {
          'question': 'q',
          'choices': ['a', 'b', 'c', 'd'],
          'answer_index': 0,
          'explanation': 'e',
        },
      ];
      final p = EventProposal.fromMap(row);
      expect(p.proposalType, 'new');
      expect(p.isNewProposal, isTrue);
      expect(p.isDeleteProposal, isFalse);
      expect(p.targetEventId, isNull);
    });

    test('delete 타입은 target_event_id + 빈 quiz_questions', () {
      final row = baseRow();
      row['proposal_type'] = 'delete';
      row['target_event_id'] = 'event-xyz';
      row['quiz_questions'] = []; // delete 는 빈 배열
      final p = EventProposal.fromMap(row);
      expect(p.isDeleteProposal, isTrue);
      expect(p.targetEventId, 'event-xyz');
      expect(p.quizQuestions, isEmpty);
    });

    test('quiz_questions jsonb 배열이 QuizDraft 리스트로 파싱된다', () {
      final row = baseRow();
      row['quiz_questions'] = [
        {
          'question': 'Q1',
          'choices': ['a1', 'b1', 'c1', 'd1'],
          'answer_index': 1,
          'explanation': 'e1',
        },
        {
          'question': 'Q2',
          'choices': ['a2', 'b2', 'c2', 'd2'],
          'answer_index': 3,
          'explanation': 'e2',
        },
      ];
      final p = EventProposal.fromMap(row);
      expect(p.quizQuestions.length, 2);
      expect(p.quizQuestions[0].question, 'Q1');
      expect(p.quizQuestions[0].answerIndex, 1);
      expect(p.quizQuestions[1].choices, ['a2', 'b2', 'c2', 'd2']);
      expect(p.quizQuestions[1].explanation, 'e2');
    });

    test('status getter들이 올바르게 동작', () {
      for (final status in ['pending', 'approved', 'rejected']) {
        final row = baseRow();
        row['status'] = status;
        row['quiz_questions'] = [
          {
            'question': 'q',
            'choices': ['a', 'b', 'c', 'd'],
            'answer_index': 0,
            'explanation': 'e',
          },
        ];
        final p = EventProposal.fromMap(row);
        expect(p.isPending, status == 'pending');
        expect(p.isApproved, status == 'approved');
        expect(p.isRejected, status == 'rejected');
      }
    });

    test('general 타입은 era_id null 허용 + image_paths 보존 + 다른 타입과 구분', () {
      final row = baseRow();
      row['proposal_type'] = 'general';
      row['era_id'] = null;
      row['target_event_id'] = null;
      row['quiz_questions'] = [];
      row['scene_image_paths'] = [];
      row['scene_image_prompts'] = [];
      row['image_paths'] = [
        'proposal-general-images/u-1/d/0.png',
        'proposal-general-images/u-1/d/1.jpg',
      ];
      final p = EventProposal.fromMap(row);
      expect(p.isGeneralProposal, isTrue);
      expect(p.isNewProposal, isFalse);
      expect(p.isDeleteProposal, isFalse);
      expect(p.eraId, isNull);
      expect(p.imagePaths, [
        'proposal-general-images/u-1/d/0.png',
        'proposal-general-images/u-1/d/1.jpg',
      ]);
    });

    test('image_paths 가 row 에 없으면 빈 배열로 파싱', () {
      final row = baseRow()
        ..['quiz_questions'] = [
          {
            'question': 'q',
            'choices': ['a', 'b', 'c', 'd'],
            'answer_index': 0,
            'explanation': 'e',
          },
        ];
      // row 에 image_paths 키 자체가 없는 경우 (구버전 row)
      final p = EventProposal.fromMap(row);
      expect(p.imagePaths, isEmpty);
    });
  });
}
