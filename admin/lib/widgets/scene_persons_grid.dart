import 'package:flutter/material.dart';

/// scene 별 등장인물 체크박스 grid.
///
/// 행: 장면 1..N (sceneCount). 열: personCodes 각각.
/// initial 은 [장면당 인물코드 리스트] 형태. 부족하면 빈 리스트로 채움.
class ScenePersonsGrid extends StatefulWidget {
  const ScenePersonsGrid({
    super.key,
    required this.personCodes,
    required this.sceneCount,
    required this.initial,
    required this.onChanged,
  });

  final List<String> personCodes;
  final int sceneCount;
  final List<List<String>> initial;
  final ValueChanged<List<List<String>>> onChanged;

  @override
  State<ScenePersonsGrid> createState() => _ScenePersonsGridState();
}

class _ScenePersonsGridState extends State<ScenePersonsGrid> {
  late List<Set<String>> _matrix; // length = sceneCount, 각 칸은 선택된 코드 set

  @override
  void initState() {
    super.initState();
    _matrix = _normalizeInitial(widget.initial, widget.sceneCount);
  }

  @override
  void didUpdateWidget(covariant ScenePersonsGrid old) {
    super.didUpdateWidget(old);
    final personsChanged =
        old.personCodes.length != widget.personCodes.length ||
        !_listEquals(old.personCodes, widget.personCodes);
    final sceneCountChanged = old.sceneCount != widget.sceneCount;
    if (personsChanged || sceneCountChanged) {
      setState(() {
        // personCodes 가 바뀌면 기존 선택 중 사라진 코드는 제거.
        final allowed = widget.personCodes.toSet();
        _matrix = List.generate(
          widget.sceneCount,
          (i) => i < _matrix.length
              ? _matrix[i].intersection(allowed)
              : <String>{},
        );
      });
    }
  }

  List<Set<String>> _normalizeInitial(List<List<String>> raw, int count) {
    return List.generate(
      count,
      (i) => i < raw.length
          ? raw[i].where(widget.personCodes.contains).toSet()
          : <String>{},
    );
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _emit() {
    widget.onChanged(_matrix.map((s) => s.toList()).toList());
  }

  void _toggle(int sceneIdx, String code, bool? value) {
    setState(() {
      if (value == true) {
        _matrix[sceneIdx].add(code);
      } else {
        _matrix[sceneIdx].remove(code);
      }
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.personCodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('등장인물 코드를 먼저 추가하면 장면별 인물 체크박스가 나타납니다.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.sceneCount; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 60,
                  child: Text(
                    '장면 ${i + 1}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    children: [
                      for (final code in widget.personCodes)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              key: ValueKey('scene_chk_${i}_$code'),
                              value: _matrix[i].contains(code),
                              onChanged: (v) => _toggle(i, code, v),
                            ),
                            Text(code),
                            const SizedBox(width: 8),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
