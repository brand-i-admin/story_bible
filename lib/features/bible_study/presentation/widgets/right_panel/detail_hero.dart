import 'package:flutter/material.dart';

class DetailHero extends StatelessWidget {
  const DetailHero({super.key, required this.emoji});

  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 120,
      margin: const EdgeInsets.only(top: 8, bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x66A07846), width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFC9A96E), Color(0xFF8B6440), Color(0xFF5C3010)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x592C1F0E)],
                  stops: [0.5, 1],
                ),
              ),
            ),
          ),
          Center(child: Text(emoji, style: const TextStyle(fontSize: 56))),
        ],
      ),
    );
  }
}
