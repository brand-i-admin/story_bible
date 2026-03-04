import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DetailTags extends StatelessWidget {
  const DetailTags({super.key, required this.places, required this.persons});

  final List<String> places;
  final List<String> persons;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      ...places.map((name) => _tag('📍 $name', true)),
      ...persons.map((name) => _tag('👤 $name', false)),
    ];

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Wrap(spacing: 5, runSpacing: 5, children: chips),
    );
  }

  Widget _tag(String text, bool place) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: place ? const Color(0x1A5A3E22) : const Color(0x143C2864),
        border: Border.all(
          color: place ? const Color(0x335A3E22) : const Color(0x263C2864),
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.notoSerifKr(
          fontSize: 9,
          color: place ? const Color(0xFF5A3E22) : const Color(0xFF3C2864),
        ),
      ),
    );
  }
}
