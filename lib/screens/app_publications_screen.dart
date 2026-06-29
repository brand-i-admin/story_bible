import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_publication.dart';
import '../state/app_publication_providers.dart';
import '../theme/tokens.dart';
import '../widgets/parchment_dialog.dart';
import '../widgets/parchment_page_scaffold.dart';

class AppPublicationsScreen extends ConsumerWidget {
  const AppPublicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final publicationsAsync = ref.watch(publishedAppPublicationsProvider);
    return ParchmentListPageScaffold(
      title: '공지사항과 사용법',
      child: ParchmentCard(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(publishedAppPublicationsProvider);
            await ref.read(publishedAppPublicationsProvider.future);
          },
          child: publicationsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(
                  '공지사항을 불러오지 못했어요.\n$error',
                  style: const TextStyle(
                    color: AppColors.brownWarm2,
                    fontSize: 13.2,
                    fontWeight: FontWeight.w800,
                    height: 1.45,
                  ),
                ),
              ],
            ),
            data: (items) {
              if (items.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 60,
                  ),
                  children: const [
                    Icon(
                      Icons.campaign_outlined,
                      size: 42,
                      color: AppColors.ink300,
                    ),
                    SizedBox(height: 12),
                    Text(
                      '아직 게시된 공지사항이 없습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.ink300,
                        fontSize: 13.2,
                        fontWeight: FontWeight.w800,
                        height: 1.5,
                      ),
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 14, color: Color(0x44BCA47A)),
                itemBuilder: (context, index) {
                  final publication = items[index];
                  return AppPublicationPreviewCard(
                    publication: publication,
                    onTap: () =>
                        showAppPublicationDetailDialog(context, publication),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class AppPublicationPreviewCard extends StatelessWidget {
  const AppPublicationPreviewCard({
    super.key,
    required this.publication,
    this.onTap,
    this.maxBodyLines = 3,
  });

  final AppPublication publication;
  final VoidCallback? onTap;
  final int maxBodyLines;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: AppColors.parchmentCream.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x66BCA47A), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${publication.category.label} · '
                '${formatAppPublicationDate(publication.displayDate)}',
                maxLines: largeText ? 2 : 1,
                overflow: largeText
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                softWrap: true,
                style: const TextStyle(
                  color: AppColors.greenBot,
                  fontSize: 11.6,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const AppPublicationBadge(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      publication.title,
                      maxLines: largeText ? 2 : 1,
                      overflow: largeText
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      softWrap: true,
                      style: const TextStyle(
                        color: AppColors.ink800,
                        fontSize: 15.2,
                        fontWeight: FontWeight.w900,
                        height: 1.22,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                publication.body,
                key: ValueKey('app-publication-preview-body-${publication.id}'),
                maxLines: largeText ? null : maxBodyLines,
                overflow: largeText
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                softWrap: true,
                style: const TextStyle(
                  color: AppColors.ink350,
                  fontSize: 12.4,
                  fontWeight: FontWeight.w700,
                  height: 1.42,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppPublicationBadge extends StatelessWidget {
  const AppPublicationBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.greenTint1,
        border: Border.all(color: AppColors.greenBot.withAlpha(0x55)),
      ),
      child: const Icon(
        Icons.campaign_rounded,
        color: AppColors.greenBot,
        size: 18,
      ),
    );
  }
}

Future<void> showAppPublicationDetailDialog(
  BuildContext context,
  AppPublication publication,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => AppPublicationDetailDialog(publication: publication),
  );
}

class AppPublicationDetailDialog extends StatelessWidget {
  const AppPublicationDetailDialog({super.key, required this.publication});

  final AppPublication publication;

  @override
  Widget build(BuildContext context) {
    return ParchmentDialog(
      title: '공지사항 상세',
      subtitle:
          '${publication.category.label} · '
          '${formatAppPublicationDate(publication.displayDate)}',
      showCloseButton: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.58,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const AppPublicationBadge(),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      publication.title,
                      style: const TextStyle(
                        color: AppColors.ink800,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppPublicationBody(
                publication: publication,
                onOpenLink: (url) => openAppPublicationLink(context, url),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppPublicationBody extends StatelessWidget {
  const AppPublicationBody({
    super.key,
    required this.publication,
    required this.onOpenLink,
  });

  final AppPublication publication;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    final lines = _displayLines();
    return Column(
      key: ValueKey('app-publication-detail-body-${publication.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          _bodyLine(lines[i]),
          if (i < lines.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _bodyLine(String rawLine) {
    final line = rawLine.trimRight();
    final linkUrl = publication.linkUrl;
    final isLinkLine =
        line == linkUrl ||
        line.startsWith('https://') ||
        line.startsWith('http://');
    if (isLinkLine) {
      return AppPublicationLinkLine(url: line, onTap: () => onOpenLink(line));
    }
    return Text(
      line,
      style: const TextStyle(
        color: AppColors.ink500,
        fontSize: 13.4,
        fontWeight: FontWeight.w700,
        height: 1.55,
      ),
    );
  }

  List<String> _displayLines() {
    final lines = publication.body.split('\n');
    final linkUrl = publication.linkUrl;
    if (linkUrl == null || lines.any((line) => line.trim() == linkUrl)) {
      return lines;
    }
    return [...lines, linkUrl];
  }
}

class AppPublicationLinkLine extends StatelessWidget {
  const AppPublicationLinkLine({super.key, required this.url, this.onTap});

  final String url;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('app-publication-link-url'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.open_in_new_rounded,
                color: AppColors.greenBot,
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  url,
                  style: const TextStyle(
                    color: AppColors.greenBot,
                    fontSize: 12.4,
                    fontWeight: FontWeight.w900,
                    height: 1.35,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openAppPublicationLink(BuildContext context, String rawUrl) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = Uri.tryParse(rawUrl);
  if (uri == null || !uri.hasScheme) {
    messenger?.showSnackBar(const SnackBar(content: Text('링크를 열 수 없어요.')));
    return;
  }
  try {
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
    if (!opened) {
      messenger?.showSnackBar(const SnackBar(content: Text('링크를 열 수 없어요.')));
    }
  } catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text('링크를 열 수 없어요.\n$error')));
  }
}

String formatAppPublicationDate(DateTime date) {
  return '${date.month}월 ${date.day}일';
}
