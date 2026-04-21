import 'package:flutter/material.dart';

/// 한국어 약어 → 책 이름. SQL 빌더의 BOOK_ABBR_TO_NO 와 일치한다.
const List<({String abbr, String name})> kBibleBooks = [
  (abbr: '창', name: '창세기'),
  (abbr: '출', name: '출애굽기'),
  (abbr: '레', name: '레위기'),
  (abbr: '민', name: '민수기'),
  (abbr: '신', name: '신명기'),
  (abbr: '수', name: '여호수아'),
  (abbr: '삿', name: '사사기'),
  (abbr: '룻', name: '룻기'),
  (abbr: '삼상', name: '사무엘상'),
  (abbr: '삼하', name: '사무엘하'),
  (abbr: '왕상', name: '열왕기상'),
  (abbr: '왕하', name: '열왕기하'),
  (abbr: '대상', name: '역대상'),
  (abbr: '대하', name: '역대하'),
  (abbr: '스', name: '에스라'),
  (abbr: '느', name: '느헤미야'),
  (abbr: '에', name: '에스더'),
  (abbr: '욥', name: '욥기'),
  (abbr: '시', name: '시편'),
  (abbr: '잠', name: '잠언'),
  (abbr: '전', name: '전도서'),
  (abbr: '아', name: '아가'),
  (abbr: '사', name: '이사야'),
  (abbr: '렘', name: '예레미야'),
  (abbr: '애', name: '예레미야애가'),
  (abbr: '겔', name: '에스겔'),
  (abbr: '단', name: '다니엘'),
  (abbr: '호', name: '호세아'),
  (abbr: '욜', name: '요엘'),
  (abbr: '암', name: '아모스'),
  (abbr: '옵', name: '오바댜'),
  (abbr: '욘', name: '요나'),
  (abbr: '미', name: '미가'),
  (abbr: '나', name: '나훔'),
  (abbr: '합', name: '하박국'),
  (abbr: '습', name: '스바냐'),
  (abbr: '학', name: '학개'),
  (abbr: '슥', name: '스가랴'),
  (abbr: '말', name: '말라기'),
  (abbr: '마', name: '마태복음'),
  (abbr: '막', name: '마가복음'),
  (abbr: '눅', name: '누가복음'),
  (abbr: '요', name: '요한복음'),
  (abbr: '행', name: '사도행전'),
  (abbr: '롬', name: '로마서'),
  (abbr: '고전', name: '고린도전서'),
  (abbr: '고후', name: '고린도후서'),
  (abbr: '갈', name: '갈라디아서'),
  (abbr: '엡', name: '에베소서'),
  (abbr: '빌', name: '빌립보서'),
  (abbr: '골', name: '골로새서'),
  (abbr: '살전', name: '데살로니가전서'),
  (abbr: '살후', name: '데살로니가후서'),
  (abbr: '딤전', name: '디모데전서'),
  (abbr: '딤후', name: '디모데후서'),
  (abbr: '딛', name: '디도서'),
  (abbr: '몬', name: '빌레몬서'),
  (abbr: '히', name: '히브리서'),
  (abbr: '약', name: '야고보서'),
  (abbr: '벧전', name: '베드로전서'),
  (abbr: '벧후', name: '베드로후서'),
  (abbr: '요일', name: '요한일서'),
  (abbr: '요이', name: '요한이서'),
  (abbr: '요삼', name: '요한삼서'),
  (abbr: '유', name: '유다서'),
  (abbr: '계', name: '요한계시록'),
];

/// 여러 개의 bible_ref ({book, from, to}) 를 카드 형태로 편집한다.
class BibleRefsPicker extends StatefulWidget {
  const BibleRefsPicker({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final List<Map<String, String>> initial;
  final ValueChanged<List<Map<String, String>>> onChanged;

  @override
  State<BibleRefsPicker> createState() => _BibleRefsPickerState();
}

class _BibleRefsPickerState extends State<BibleRefsPicker> {
  late List<Map<String, String>> _refs;
  late List<TextEditingController> _fromCtrls;
  late List<TextEditingController> _toCtrls;

  @override
  void initState() {
    super.initState();
    _refs = widget.initial.map(Map<String, String>.from).toList();
    _fromCtrls = _refs
        .map((r) => TextEditingController(text: r['from'] ?? ''))
        .toList();
    _toCtrls = _refs
        .map((r) => TextEditingController(text: r['to'] ?? ''))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _fromCtrls) {
      c.dispose();
    }
    for (final c in _toCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit() =>
      widget.onChanged(_refs.map(Map<String, String>.from).toList());

  void _addNew() {
    setState(() {
      _refs.add({'book': '창', 'from': '1:1', 'to': '1:1'});
      _fromCtrls.add(TextEditingController(text: '1:1'));
      _toCtrls.add(TextEditingController(text: '1:1'));
    });
    _emit();
  }

  void _remove(int index) {
    setState(() {
      _refs.removeAt(index);
      _fromCtrls.removeAt(index).dispose();
      _toCtrls.removeAt(index).dispose();
    });
    _emit();
  }

  void _update(int index, String key, String value) {
    setState(() => _refs[index][key] = value);
    _emit();
  }

  String _displayText(Map<String, String> r) {
    final book = r['book'] ?? '';
    final from = r['from'] ?? '';
    final to = r['to'] ?? '';
    if (from.isEmpty) return book;
    if (to.isEmpty || from == to) return '$book $from';
    return '$book $from-$to';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _refs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _displayText(_refs[i]),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        IconButton(
                          key: ValueKey('bible_ref_remove_$i'),
                          tooltip: '삭제',
                          onPressed: () => _remove(i),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('bible_ref_book_$i'),
                            value: _refs[i]['book'],
                            isDense: true,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '책',
                              isDense: true,
                            ),
                            items: kBibleBooks
                                .map(
                                  (b) => DropdownMenuItem(
                                    value: b.abbr,
                                    child: Text(
                                      b.abbr,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) _update(i, 'book', v);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: ValueKey('bible_ref_from_$i'),
                            controller: _fromCtrls[i],
                            decoration: const InputDecoration(
                              labelText: 'from (장:절)',
                              hintText: '1:1',
                              isDense: true,
                            ),
                            onChanged: (v) => _update(i, 'from', v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: ValueKey('bible_ref_to_$i'),
                            controller: _toCtrls[i],
                            decoration: const InputDecoration(
                              labelText: 'to (장:절)',
                              hintText: '2:3',
                              isDense: true,
                            ),
                            onChanged: (v) => _update(i, 'to', v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('bible_refs_add'),
            onPressed: _addNew,
            icon: const Icon(Icons.add),
            label: const Text('성경 본문 추가'),
          ),
        ),
      ],
    );
  }
}
