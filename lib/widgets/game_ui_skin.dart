import 'package:flutter/material.dart';

const String kPanelFrameAsset = 'assets/elements/panel_left_and_right.png';
const String kTabItemInactiveAsset = 'assets/elements/tab_item_inactive.png';
const String kTabItemActiveAsset = 'assets/elements/tab_item_active.png';
const String kTabBarAsset = 'assets/elements/tab_bar.png';
const String kHeaderBadgeAsset = 'assets/elements/header_badge.png';
const String kBtnDefaultAsset = 'assets/elements/btn_default.png';
const String kBtnSelectedAsset = 'assets/elements/btn_selected.png';
const String kShortDescriptionAsset = 'assets/elements/scroll_popup.png';
const String kScrollPopupAsset = 'assets/elements/scroll_popup.png';
const String kScrollCloseAsset = 'assets/elements/scroll_close.png';
const String kPinNormalAsset = 'assets/elements/pin_normal.png';
const String kPinSelectedAsset = 'assets/elements/pin_selected.png';
const String kStatesBtnAsset = 'assets/elements/states_btn.png';
const String kBookButtonAsset = 'assets/elements/book_button.png';
const String kProfileButtonAsset = 'assets/elements/profile_button.png';

EdgeInsets panelContentPaddingForSize(Size size) {
  final width = size.width.isFinite ? size.width : 220.0;
  final height = size.height.isFinite ? size.height : 620.0;
  // panel_left_and_right.png (cropped, no external padding):
  // Top scroll decoration ends ~10% from top; bottom decoration starts ~8% from bottom.
  final horizontal = (width * 0.075).clamp(9.0, 16.0).toDouble();
  final top = (height * 0.10).clamp(50.0, 90.0).toDouble();
  final bottom = (height * 0.08).clamp(28.0, 55.0).toDouble();
  return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
}

BoxDecoration panelLabelBackdropDecoration() {
  return BoxDecoration(
    color: const Color(0xB3472F17),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: const Color(0x99DDB883), width: 1),
  );
}

BoxDecoration panelFrameDecoration() {
  return const BoxDecoration(
    image: DecorationImage(
      image: AssetImage(kPanelFrameAsset),
      fit: BoxFit.fill,
    ),
  );
}

// tab_item_inactive/active.png: use BoxFit.fill so both images render
// at exactly the same size regardless of their different source dimensions.
BoxDecoration tabItemDecoration({required bool selected}) {
  return BoxDecoration(
    image: DecorationImage(
      image: AssetImage(selected ? kTabItemActiveAsset : kTabItemInactiveAsset),
      fit: BoxFit.fill,
    ),
  );
}

// tab_bar.png (1408×768): has two visible horizontal rails at 29.7% and 63.5%
// of image height; everything else is transparent. No solid background — the
// image provides its own wooden rail decoration.
BoxDecoration tabBarDecoration() {
  return const BoxDecoration(
    image: DecorationImage(image: AssetImage(kTabBarAsset), fit: BoxFit.fill),
  );
}

BoxDecoration headerBadgeDecoration() {
  return const BoxDecoration(
    image: DecorationImage(
      image: AssetImage(kHeaderBadgeAsset),
      fit: BoxFit.fill,
    ),
  );
}

BoxDecoration statesButtonDecoration() {
  return const BoxDecoration(
    image: DecorationImage(
      image: AssetImage(kStatesBtnAsset),
      fit: BoxFit.fill,
    ),
  );
}

Widget statesButtonLabel({
  required String text,
  double width = 124,
  double height = 35,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 7,
  ),
  double fontSize = 12,
  FontWeight fontWeight = FontWeight.w800,
  Color color = const Color(0xFFFDF8EE),
}) {
  return SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: statesButtonDecoration(),
      child: Padding(
        padding: padding,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: fontWeight,
                color: color,
                shadows: const [
                  Shadow(
                    color: Color(0xAA000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// btn_default/selected.png: oval-shaped button, content at rows 29-70%.
// fitWidth + center alignment shows the oval center within any container height.
BoxDecoration actionButtonDecoration({required bool selected}) {
  return BoxDecoration(
    image: DecorationImage(
      image: AssetImage(selected ? kBtnSelectedAsset : kBtnDefaultAsset),
      fit: BoxFit.fitWidth,
      alignment: Alignment.center,
    ),
  );
}

BoxDecoration shortDescriptionDecoration() {
  return const BoxDecoration(
    image: DecorationImage(
      image: AssetImage(kShortDescriptionAsset),
      fit: BoxFit.fill,
    ),
  );
}

// scroll_popup.png: transparent center with decorative rollers at top (~12-18%)
// and bottom (~74-88%). Background is transparent so only the scroll frame is
// visible; content is clipped inside the inner parchment area via Positioned.
BoxDecoration scrollPopupDecoration() {
  return const BoxDecoration(
    image: DecorationImage(
      image: AssetImage(kScrollPopupAsset),
      fit: BoxFit.fill,
    ),
  );
}
