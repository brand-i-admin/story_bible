import 'package:flutter/material.dart';

import '../models/story_event.dart';

class SearchBox extends StatelessWidget {
  const SearchBox({
    super.key,
    required this.value,
    required this.results,
    required this.onChanged,
    required this.onSelect,
  });

  final String value;
  final List<StoryEvent> results;
  final ValueChanged<String> onChanged;
  final ValueChanged<StoryEvent> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextFormField(
          key: ValueKey(value),
          initialValue: value,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: '단어/문장 검색...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: const Color(0xFFF4E8D4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFBDA076)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFBDA076)),
            ),
          ),
        ),
        if (value.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF0DE),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBDA076)),
            ),
            child: results.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('검색 결과가 없습니다.'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final event = results[index];
                      return ListTile(
                        dense: true,
                        title: Text(event.title),
                        subtitle: Text(event.placeName ?? '-'),
                        onTap: () => onSelect(event),
                      );
                    },
                  ),
          ),
      ],
    );
  }
}
