import 'package:flutter_test/flutter_test.dart';

import 'package:story_bible/state/story_state.dart';
import 'package:story_bible/utils/home_back_navigation.dart';

void main() {
  group('resolveHomeBackAction', () {
    test('exits app when home has no selected era', () {
      expect(
        resolveHomeBackAction(
          selectedEraId: null,
          selectionMode: null,
          selectionStep: 1,
          selectedLandmarkId: null,
        ),
        HomeBackAction.exitApp,
      );
    });

    test('clears era selection from intro after choosing an era', () {
      expect(
        resolveHomeBackAction(
          selectedEraId: 'era-exodus',
          selectionMode: null,
          selectionStep: 1,
          selectedLandmarkId: null,
        ),
        HomeBackAction.clearEraSelection,
      );
    });

    test('returns from region event list to region picker', () {
      expect(
        resolveHomeBackAction(
          selectedEraId: 'era-exodus',
          selectionMode: SelectionMode.region,
          selectionStep: 2,
          selectedLandmarkId: 'landmark-sinai',
        ),
        HomeBackAction.returnToRegionPicker,
      );
    });

    test('returns from region picker to home', () {
      expect(
        resolveHomeBackAction(
          selectedEraId: 'era-exodus',
          selectionMode: SelectionMode.region,
          selectionStep: 2,
          selectedLandmarkId: null,
        ),
        HomeBackAction.returnToHome,
      );
    });

    test('returns from character events to character picker', () {
      expect(
        resolveHomeBackAction(
          selectedEraId: 'era-exodus',
          selectionMode: SelectionMode.character,
          selectionStep: 3,
          selectedLandmarkId: null,
        ),
        HomeBackAction.returnToCharacterPicker,
      );
    });

    test('returns from character picker to home', () {
      expect(
        resolveHomeBackAction(
          selectedEraId: 'era-exodus',
          selectionMode: SelectionMode.character,
          selectionStep: 2,
          selectedLandmarkId: null,
        ),
        HomeBackAction.returnToHome,
      );
    });

    test('returns from timeline mode to home', () {
      expect(
        resolveHomeBackAction(
          selectedEraId: 'era-exodus',
          selectionMode: SelectionMode.timeline,
          selectionStep: 3,
          selectedLandmarkId: null,
        ),
        HomeBackAction.returnToHome,
      );
    });
  });
}
