import 'package:flutter/material.dart';

class PersonOption {
  const PersonOption({required this.code, required this.name});
  final String code;
  final String name;
}

/// 등록 폼 안에서 인물 코드 리스트를 관리한다.
///
/// - DB 의 persons 테이블에서 가져온 [available] 을 자동완성 후보로 보여준다.
/// - 사용자는 자유롭게 신규 코드도 입력할 수 있다 (배포 시 placeholder 로 자동 생성).
/// - 선택된 코드는 chip 으로 보여주고, x 로 제거 가능.
class PersonCodesPicker extends StatefulWidget {
  const PersonCodesPicker({
    super.key,
    required this.available,
    required this.initial,
    required this.onChanged,
  });

  final List<PersonOption> available;
  final List<String> initial;
  final ValueChanged<List<String>> onChanged;

  @override
  State<PersonCodesPicker> createState() => _PersonCodesPickerState();
}

class _PersonCodesPickerState extends State<PersonCodesPicker> {
  late List<String> _selected;
  final _inputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = [...widget.initial];
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged([..._selected]);

  void _add(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return;
    if (_selected.contains(code)) return;
    setState(() {
      _selected.add(code);
      _inputCtrl.clear();
    });
    _emit();
  }

  void _remove(String code) {
    setState(() => _selected.remove(code));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final code in _selected)
              InputChip(
                key: ValueKey('person_chip_$code'),
                label: Text(code),
                onDeleted: () => _remove(code),
                deleteIcon: Icon(
                  Icons.close,
                  key: ValueKey('person_chip_remove_$code'),
                  size: 16,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Autocomplete<PersonOption>(
                optionsBuilder: (text) {
                  final q = text.text.trim().toLowerCase();
                  if (q.isEmpty) return const Iterable<PersonOption>.empty();
                  return widget.available.where(
                    (o) =>
                        o.code.toLowerCase().contains(q) ||
                        o.name.toLowerCase().contains(q),
                  );
                },
                displayStringForOption: (o) => '${o.code} (${o.name})',
                onSelected: (o) => _add(o.code),
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      // 외부에서 _inputCtrl 와 연동하기 위해 매 빌드마다 동기화.
                      if (controller.text != _inputCtrl.text) {
                        controller.text = _inputCtrl.text;
                      }
                      controller.addListener(() {
                        if (_inputCtrl.text != controller.text) {
                          _inputCtrl.text = controller.text;
                        }
                      });
                      return TextField(
                        key: const ValueKey('person_picker_input'),
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: '인물 코드 (자동완성 또는 직접 입력)',
                          hintText: '예: peter',
                        ),
                        onSubmitted: (_) {
                          _add(controller.text);
                          controller.clear();
                        },
                      );
                    },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              key: const ValueKey('person_picker_add'),
              onPressed: () => _add(_inputCtrl.text),
              child: const Text('추가'),
            ),
          ],
        ),
      ],
    );
  }
}
