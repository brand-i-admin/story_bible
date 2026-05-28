import '../state/story_state.dart';

enum HomeBackAction {
  exitApp,
  clearEraSelection,
  returnToHome,
  returnToRegionPicker,
  returnToCharacterPicker,
}

HomeBackAction resolveHomeBackAction({
  required String? selectedEraId,
  required SelectionMode? selectionMode,
  required int selectionStep,
  required String? selectedLandmarkId,
}) {
  if (selectedEraId == null) {
    return HomeBackAction.exitApp;
  }

  if (selectionMode == null) {
    return HomeBackAction.clearEraSelection;
  }

  switch (selectionMode) {
    case SelectionMode.region:
      if (selectedLandmarkId != null) {
        return HomeBackAction.returnToRegionPicker;
      }
      return HomeBackAction.returnToHome;
    case SelectionMode.character:
      if (selectionStep >= 3) {
        return HomeBackAction.returnToCharacterPicker;
      }
      return HomeBackAction.returnToHome;
  }
}
