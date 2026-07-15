import 'package:flutter/material.dart';

import '../theme/app_color_palette.dart';

class LegalDocumentsScreen extends StatelessWidget {
  const LegalDocumentsScreen({super.key});

  static const _operatorName = 'Story Bible';
  static const _contactEmail = 'admin@brand-i.net';
  static const _effectiveDate = '2026-05-15';

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Scaffold(
      backgroundColor: palette.pageBottom,
      body: Stack(
        children: [
          Positioned.fill(child: _LegalBackground(palette: palette)),
          SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(48, 18, 20, 18),
                    child: Container(
                      key: const ValueKey('legal-documents-outer-surface'),
                      decoration: _panelDecoration(palette),
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                      child: ListView(
                        children: [
                          Text(
                            '법적 안내',
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '앱 안에서는 아래에서 바로 확인할 수 있고, 공개용 웹 문서는 https://brand-i-admin.github.io/story-bible-pages/ 에서 확인할 수 있습니다.',
                            style: TextStyle(
                              color: palette.mutedText,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Row(
                            children: [
                              Expanded(
                                child: _LegalMetaCard(
                                  label: '운영자',
                                  value: LegalDocumentsScreen._operatorName,
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _LegalMetaCard(
                                  label: '문의 이메일',
                                  value: LegalDocumentsScreen._contactEmail,
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: _LegalMetaCard(
                                  label: '시행일',
                                  value: LegalDocumentsScreen._effectiveDate,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _LegalDocCard(
                            icon: Icons.description_outlined,
                            title: '서비스 이용약관',
                            subtitle:
                                '계정, 서비스 이용, 금지행위, 책임 제한, 탈퇴 및 문의 기준을 안내합니다.',
                            filePath:
                                'https://brand-i-admin.github.io/story-bible-pages/terms-of-service.html',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const _LegalDocumentDetailScreen(
                                        document: _termsDocument,
                                      ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          _LegalDocCard(
                            icon: Icons.verified_user_outlined,
                            title: '개인정보 처리방침',
                            subtitle:
                                '로그인, 프로필, 저장한 이야기와 말씀, 기도제목 공유 기능에서 처리되는 개인정보 기준을 안내합니다.',
                            filePath:
                                'https://brand-i-admin.github.io/story-bible-pages/privacy-policy.html',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      const _LegalDocumentDetailScreen(
                                        document: _privacyDocument,
                                      ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  child: _CompactBackButton(
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalDocumentDetailScreen extends StatelessWidget {
  const _LegalDocumentDetailScreen({required this.document});

  final _LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Scaffold(
      backgroundColor: palette.pageBottom,
      body: Stack(
        children: [
          Positioned.fill(child: _LegalBackground(palette: palette)),
          SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(48, 18, 20, 18),
                    child: Container(
                      decoration: _panelDecoration(palette),
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                      child: SelectionArea(
                        child: ListView(
                          children: [
                            Text(
                              document.title,
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              document.summary,
                              style: TextStyle(
                                color: palette.mutedText,
                                fontSize: 13.6,
                                fontWeight: FontWeight.w700,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _MetaPill(
                                  label: '시행일 ${document.effectiveDate}',
                                ),
                                _MetaPill(
                                  label: '최종 수정일 ${document.updatedDate}',
                                ),
                                _MetaPill(label: '문의 ${document.contactEmail}'),
                              ],
                            ),
                            const SizedBox(height: 18),
                            ...document.sections.map(
                              (section) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Container(
                                  decoration: _cardDecoration(palette),
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    15,
                                    16,
                                    15,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        section.title,
                                        style: TextStyle(
                                          color: palette.primaryDeep,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ...section.paragraphs.map(
                                        (paragraph) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Text(
                                            paragraph,
                                            style: TextStyle(
                                              color: palette.mutedText,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              height: 1.6,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  child: _CompactBackButton(
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalDocCard extends StatelessWidget {
  const _LegalDocCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.filePath,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String filePath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: _cardDecoration(palette),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [palette.currentAccent, palette.primary],
                  ),
                ),
                child: Icon(icon, color: palette.activeTextOnAccent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: palette.mutedText,
                        fontSize: 11.2,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      filePath,
                      style: TextStyle(
                        color: palette.primaryDeep,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: palette.mutedText,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalMetaCard extends StatelessWidget {
  const _LegalMetaCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      decoration: _cardDecoration(palette),
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: palette.text,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.mutedSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.subtleBorder, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.mutedText,
          fontSize: 11.4,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CompactBackButton extends StatelessWidget {
  const _CompactBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.actionTop, palette.actionBottom],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.actionBorder, width: 1.1),
          ),
          child: Icon(
            Icons.chevron_left_rounded,
            color: palette.activeTextOnAccent,
            size: 26,
          ),
        ),
      ),
    );
  }
}

class _LegalBackground extends StatelessWidget {
  const _LegalBackground({required this.palette});

  final AppColorPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: palette.pageGradient,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.25, -0.65),
                  radius: 1.0,
                  colors: [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: palette == AppColorPalette.blackMap ? 0.06 : 0.08,
                child: CustomPaint(
                  painter: _CrossGridPainter(color: palette.subtleBorder),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrossGridPainter extends CustomPainter {
  const _CrossGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 36.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CrossGridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

BoxDecoration _panelDecoration(AppColorPalette palette) {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [palette.panelSurface, palette.mutedSurface],
    ),
    borderRadius: BorderRadius.circular(28),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(
          alpha: palette == AppColorPalette.blackMap ? 0.36 : 0.14,
        ),
        blurRadius: 24,
        offset: const Offset(0, 12),
      ),
    ],
  );
}

BoxDecoration _cardDecoration(AppColorPalette palette) {
  return BoxDecoration(
    color: palette.cardSurface,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: palette.subtleBorder, width: 1),
  );
}

class _LegalDocument {
  const _LegalDocument({
    required this.title,
    required this.summary,
    required this.effectiveDate,
    required this.updatedDate,
    required this.contactEmail,
    required this.sections,
  });

  final String title;
  final String summary;
  final String effectiveDate;
  final String updatedDate;
  final String contactEmail;
  final List<_LegalSection> sections;
}

class _LegalSection {
  const _LegalSection({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

const _termsDocument = _LegalDocument(
  title: '서비스 이용약관',
  summary:
      'Story Bible(이야기 성경) 서비스 이용과 관련한 계정, 기능, 금지행위, 탈퇴 및 책임 제한 기준을 안내합니다.',
  effectiveDate: '2026-05-15',
  updatedDate: '2026-05-15',
  contactEmail: 'admin@brand-i.net',
  sections: [
    _LegalSection(
      title: '1. 목적',
      paragraphs: [
        '이 약관은 Story Bible(이야기 성경) 운영자가 제공하는 성경 이야기 탐색, 지도 보기, 인물 학습, 이야기와 말씀 저장, 기도제목 공유 기능의 이용과 관련하여 운영자와 이용자 간 권리와 의무를 정하는 것을 목적으로 합니다.',
      ],
    ),
    _LegalSection(
      title: '2. 서비스 내용',
      paragraphs: [
        '이용자는 로그인 없이도 성경 이야기, 사건 지도, 금주 인물, 퀴즈 일부 기능을 사용할 수 있습니다.',
        '로그인 이용자는 프로필 저장, 이야기와 말씀 저장, 기도제목 등록 및 공유, 학습 진행 상황 저장 기능을 사용할 수 있습니다.',
      ],
    ),
    _LegalSection(
      title: '3. 계정과 이용자 책임',
      paragraphs: [
        '로그인 이용자는 Apple, Google 또는 Kakao 계정을 통해 본인 인증을 수행하며, 자신의 계정 정보를 안전하게 관리해야 합니다.',
        '타인의 계정이나 공유 ID를 무단으로 사용하거나, 서비스 운영을 방해하는 방식으로 반복 요청을 보내서는 안 됩니다.',
      ],
    ),
    _LegalSection(
      title: '4. 이용 제한',
      paragraphs: [
        '운영자는 서비스 안정성을 해치거나, 다른 이용자에게 피해를 주는 행위가 확인되는 경우 일부 기능 이용을 제한할 수 있습니다.',
      ],
    ),
    _LegalSection(
      title: '5. 저장 콘텐츠',
      paragraphs: [
        '이용자가 저장한 이야기와 말씀, 프로필 정보, 기도제목은 이용자 본인의 책임 아래 관리됩니다.',
        '공유 ID를 통해 다른 사람의 기도제목을 추가한 경우, 그 정보는 이용자가 직접 삭제하기 전까지 자신의 계정에 표시될 수 있습니다.',
      ],
    ),
    _LegalSection(
      title: '6. 서비스 변경 및 중단',
      paragraphs: [
        '운영자는 서비스 품질 개선, 오류 수정, 정책 변경을 위해 기능을 수정하거나 일부 서비스를 중단할 수 있습니다.',
      ],
    ),
    _LegalSection(
      title: '7. 책임 제한',
      paragraphs: [
        '운영자는 천재지변, 네트워크 장애, 외부 인증 제공자 또는 인프라 사업자의 장애 등 불가항력적 사유로 발생한 손해에 대해 법령이 허용하는 범위에서 책임을 제한할 수 있습니다.',
      ],
    ),
    _LegalSection(
      title: '8. 문의',
      paragraphs: ['서비스 관련 문의는 이메일(admin@brand-i.net)로 접수할 수 있습니다.'],
    ),
  ],
);

const _privacyDocument = _LegalDocument(
  title: '개인정보 처리방침',
  summary:
      'Story Bible(이야기 성경)에서 로그인, 프로필 저장, 이야기와 말씀 저장, 기도제목 공유 기능을 제공하는 과정에서 처리되는 개인정보 기준을 안내합니다.',
  effectiveDate: '2026-05-15',
  updatedDate: '2026-05-15',
  contactEmail: 'admin@brand-i.net',
  sections: [
    _LegalSection(
      title: '1. 수집하는 정보',
      paragraphs: [
        '소셜 로그인 시 Apple, Google 또는 Kakao로부터 이용자가 동의한 범위의 계정 식별 정보, 이메일, 공개 프로필 정보가 제공될 수 있습니다.',
        '앱에서는 닉네임, 프로필 사진, 기도제목, 저장한 이야기와 말씀, 퀴즈 진행 기록, 공유받은 기도제목 목록을 저장할 수 있습니다.',
      ],
    ),
    _LegalSection(
      title: '2. 이용 목적',
      paragraphs: [
        '계정 생성 및 로그인 유지, 프로필 표시, 이야기와 말씀 저장, 기도제목 공유, 학습 진행 상황 저장, 서비스 안정성 확보를 위해 개인정보를 처리합니다.',
      ],
    ),
    _LegalSection(
      title: '3. 보관 기간',
      paragraphs: [
        '회원 탈퇴 또는 이용 목적 달성 시 관련 정보를 지체 없이 삭제하는 것을 원칙으로 합니다.',
        '다만 법령상 보관 의무가 있거나 분쟁 대응이 필요한 경우 필요한 범위에서 일정 기간 보관할 수 있습니다.',
      ],
    ),
    _LegalSection(
      title: '4. 제3자 제공 및 위탁',
      paragraphs: [
        '운영자는 원칙적으로 개인정보를 제3자에게 판매하거나 임의 제공하지 않습니다.',
        '서비스 운영을 위해 Supabase를 데이터베이스 및 저장소 인프라로 사용하며, Apple/Google/Kakao 로그인 시 해당 인증 사업자를 이용합니다.',
      ],
    ),
    _LegalSection(
      title: '5. 기도제목 공유 기능',
      paragraphs: [
        '이용자에게는 중복되지 않는 7자리 공유 ID가 부여될 수 있으며, 다른 이용자가 이 ID를 직접 입력한 경우에만 해당 이용자의 닉네임, 프로필 사진, 기도제목이 상대방의 중보 목록에 표시됩니다.',
      ],
    ),
    _LegalSection(
      title: '6. 이용자 권리',
      paragraphs: [
        '이용자는 자신의 프로필, 저장한 이야기와 말씀, 기도제목을 수정하거나 삭제할 수 있으며, 계정 탈퇴를 요청할 수 있습니다.',
      ],
    ),
    _LegalSection(
      title: '7. 안전성 확보 조치',
      paragraphs: [
        '운영자는 인증, 접근 통제, 전송 구간 보호, 서비스 업데이트 등 합리적인 범위의 보호 조치를 시행합니다.',
      ],
    ),
    _LegalSection(
      title: '8. 문의',
      paragraphs: ['개인정보 처리에 관한 문의는 이메일(admin@brand-i.net)로 접수할 수 있습니다.'],
    ),
  ],
);
