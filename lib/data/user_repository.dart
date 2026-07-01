import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import '../models/bible_verse.dart';
import '../models/character.dart';
import '../models/character_study_progress.dart';
import '../models/intercessory_prayer_item.dart';
import '../models/paged_result.dart';
import '../models/saved_bible_verse.dart';
import '../models/user_companion_diary_entry.dart';

class UserRepository {
  const UserRepository(this._client);

  static const profileImageBucket = 'profile-images';
  static const _savedVerseColumns =
      'id, user_id, translation, book_no, book_name, chapter_no, verse_no, verse_text, comment, is_saved, highlight_color, created_at, updated_at';
  static const _savedVerseCommentMaxLength = 200;
  static const _companionDiaryColumns =
      'id, user_id, entry_date, title, body, created_at, updated_at';
  static const companionDiaryTitleMaxLength = 80;
  static const companionDiaryBodyMaxLength = 1000;

  final SupabaseClient _client;

  Future<AppUserProfile> ensureSignedInUser(
    User user, {
    String? nicknameHint,
  }) async {
    final existing = await _fetchProfileOrNull(user.id);
    if (existing == null) {
      final nickname = _deriveNickname(user, nicknameHint);
      await _client.from('user_profiles').insert({
        'user_id': user.id,
        'nickname': nickname,
      });
    } else if (existing.nickname.trim().isEmpty) {
      await _client
          .from('user_profiles')
          .update({'nickname': _deriveNickname(user, nicknameHint)})
          .eq('user_id', user.id);
    }

    return fetchUserProfile(user.id);
  }

  Future<AppUserProfile> fetchUserProfile(String userId) async {
    final row = await _client
        .from('user_profiles')
        .select(
          'user_id, share_id, nickname, photo_url, prayer_request, created_at, updated_at',
        )
        .eq('user_id', userId)
        .single();
    return AppUserProfile.fromMap(row);
  }

  /// user_profiles.is_pastor 플래그 조회. RLS 상 본인 행만 읽을 수 있으므로
  /// 호출자는 `userId == auth.uid()` 이어야 한다. 미로그인/미존재 시 false.
  Future<bool> fetchIsPastor(String userId) async {
    final row = await _client
        .from('user_profiles')
        .select('is_pastor')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return false;
    return (row['is_pastor'] as bool?) ?? false;
  }

  Future<AppUserProfile> updateUserProfile({
    required String userId,
    required String nickname,
    required String? prayerRequest,
    String? photoUrl,
  }) async {
    final row = await _client
        .from('user_profiles')
        .update({
          'nickname': nickname.trim(),
          'prayer_request': _cleanNullableText(prayerRequest),
          if (photoUrl != null) 'photo_url': photoUrl,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('user_id', userId)
        .select(
          'user_id, share_id, nickname, photo_url, prayer_request, created_at, updated_at',
        )
        .single();

    return AppUserProfile.fromMap(row);
  }

  Future<String> uploadProfileImage({
    required String userId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final normalizedExtension = _normalizeExtension(extension);
    final path =
        '$userId/profile_${DateTime.now().millisecondsSinceEpoch}.$normalizedExtension';
    await _client.storage
        .from(profileImageBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: _contentTypeForExtension(normalizedExtension),
          ),
        );
    return _client.storage.from(profileImageBucket).getPublicUrl(path);
  }

  Future<PagedResult<SavedBibleVerse>> fetchSavedVersesPage({
    required String userId,
    required int pageIndex,
    int pageSize = 10,
  }) async {
    final from = pageIndex * pageSize;
    final to = from + pageSize;
    final rows = await _client
        .from('user_saved_verses')
        .select(_savedVerseColumns)
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .order('created_at', ascending: false)
        .range(from, to);

    final verses = rows
        .map<SavedBibleVerse>((row) => SavedBibleVerse.fromMap(row))
        .toList();
    final hasNextPage = verses.length > pageSize;
    return PagedResult<SavedBibleVerse>(
      items: hasNextPage ? verses.take(pageSize).toList() : verses,
      pageIndex: pageIndex,
      pageSize: pageSize,
      hasNextPage: hasNextPage,
    );
  }

  Future<Map<String, SavedBibleVerse>> fetchSavedVerseMap(String userId) async {
    final rows = await _client
        .from('user_saved_verses')
        .select(_savedVerseColumns)
        .eq('user_id', userId);

    return {
      for (final row in rows.map<SavedBibleVerse>(SavedBibleVerse.fromMap))
        row.key: row,
    };
  }

  Future<SavedBibleVerse> saveBibleVerse({
    required String userId,
    required BibleVerse verse,
    String comment = '',
  }) async {
    final normalizedComment = _normalizeSavedVerseComment(comment);
    final existing = await _fetchSavedVerseForVerse(
      userId: userId,
      verse: verse,
    );
    final payload = {
      'user_id': userId,
      'translation': verse.translation,
      'book_no': verse.bookNo,
      'book_name': verse.bookName,
      'chapter_no': verse.chapterNo,
      'verse_no': verse.verseNo,
      'verse_text': verse.verseText,
      'comment': normalizedComment,
      'is_saved': true,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final row = existing == null
        ? await _client
              .from('user_saved_verses')
              .insert(payload)
              .select(_savedVerseColumns)
              .single()
        : await _client
              .from('user_saved_verses')
              .update(payload)
              .eq('id', existing.id)
              .select(_savedVerseColumns)
              .single();
    return SavedBibleVerse.fromMap(row);
  }

  Future<SavedBibleVerse> setBibleVerseHighlight({
    required String userId,
    required BibleVerse verse,
    required String highlightColor,
  }) async {
    final normalizedColor = SavedBibleVerse.normalizeHighlightColor(
      highlightColor,
    );
    if (normalizedColor == null) {
      throw ArgumentError.value(
        highlightColor,
        'highlightColor',
        'blue 또는 yellow만 사용할 수 있습니다.',
      );
    }
    final existing = await _fetchSavedVerseForVerse(
      userId: userId,
      verse: verse,
    );
    final updatedAt = DateTime.now().toIso8601String();
    final row = existing == null
        ? await _client
              .from('user_saved_verses')
              .insert({
                'user_id': userId,
                'translation': verse.translation,
                'book_no': verse.bookNo,
                'book_name': verse.bookName,
                'chapter_no': verse.chapterNo,
                'verse_no': verse.verseNo,
                'verse_text': verse.verseText,
                'comment': '',
                'is_saved': false,
                'highlight_color': normalizedColor,
                'updated_at': updatedAt,
              })
              .select(_savedVerseColumns)
              .single()
        : await _client
              .from('user_saved_verses')
              .update({
                'book_name': verse.bookName,
                'verse_text': verse.verseText,
                'highlight_color': normalizedColor,
                'updated_at': updatedAt,
              })
              .eq('id', existing.id)
              .select(_savedVerseColumns)
              .single();
    return SavedBibleVerse.fromMap(row);
  }

  Future<SavedBibleVerse?> clearBibleVerseHighlight({
    required String userId,
    required BibleVerse verse,
  }) async {
    final existing = await _fetchSavedVerseForVerse(
      userId: userId,
      verse: verse,
    );
    if (existing == null) {
      return null;
    }
    if (!existing.isSaved) {
      await _client.from('user_saved_verses').delete().eq('id', existing.id);
      return null;
    }

    final row = await _client
        .from('user_saved_verses')
        .update({
          'book_name': verse.bookName,
          'verse_text': verse.verseText,
          'highlight_color': null,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', existing.id)
        .select(_savedVerseColumns)
        .single();
    return SavedBibleVerse.fromMap(row);
  }

  Future<SavedBibleVerse?> _fetchSavedVerseForVerse({
    required String userId,
    required BibleVerse verse,
  }) async {
    final row = await _client
        .from('user_saved_verses')
        .select(_savedVerseColumns)
        .eq('user_id', userId)
        .eq('translation', verse.translation)
        .eq('book_no', verse.bookNo)
        .eq('chapter_no', verse.chapterNo)
        .eq('verse_no', verse.verseNo)
        .maybeSingle();
    return row == null ? null : SavedBibleVerse.fromMap(row);
  }

  Future<void> deleteSavedVerse(String verseId) {
    return _client.from('user_saved_verses').delete().eq('id', verseId);
  }

  Future<List<UserCompanionDiaryEntry>> fetchCompanionDiaryEntries({
    required String userId,
  }) async {
    final rows = await _client
        .from('user_companion_diary_entries')
        .select(_companionDiaryColumns)
        .eq('user_id', userId)
        .order('entry_date', ascending: false)
        .order('updated_at', ascending: false);

    return rows
        .map<UserCompanionDiaryEntry>(UserCompanionDiaryEntry.fromMap)
        .toList(growable: false);
  }

  Future<UserCompanionDiaryEntry> upsertCompanionDiaryEntry({
    required String userId,
    required DateTime entryDate,
    required String title,
    required String body,
  }) async {
    final normalizedTitle = normalizeCompanionDiaryTitle(title);
    final normalizedBody = normalizeCompanionDiaryBody(body);
    if (normalizedTitle.isEmpty || normalizedBody.isEmpty) {
      throw ArgumentError('제목과 본문을 입력해 주세요.');
    }

    final row = await _client
        .from('user_companion_diary_entries')
        .upsert({
          'user_id': userId,
          'entry_date': companionDiaryDateKey(entryDate),
          'title': normalizedTitle,
          'body': normalizedBody,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,entry_date')
        .select(_companionDiaryColumns)
        .single();
    return UserCompanionDiaryEntry.fromMap(row);
  }

  Future<void> deleteCompanionDiaryEntry({
    required String userId,
    required DateTime entryDate,
  }) {
    return _client
        .from('user_companion_diary_entries')
        .delete()
        .eq('user_id', userId)
        .eq('entry_date', companionDiaryDateKey(entryDate));
  }

  String _normalizeSavedVerseComment(String comment) {
    final trimmed = comment.trim();
    if (trimmed.length <= _savedVerseCommentMaxLength) {
      return trimmed;
    }
    return trimmed.substring(0, _savedVerseCommentMaxLength);
  }

  Future<PagedResult<IntercessoryPrayerItem>> fetchIntercessoryPrayerPage({
    required int pageIndex,
    int pageSize = 12,
  }) async {
    final offset = pageIndex * pageSize;
    final rows = await _client.rpc(
      'list_intercessory_prayer_requests',
      params: {'p_limit': pageSize + 1, 'p_offset': offset},
    );

    final items = (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map<IntercessoryPrayerItem>(IntercessoryPrayerItem.fromMap)
        .toList(growable: false);
    final hasNextPage = items.length > pageSize;
    return PagedResult<IntercessoryPrayerItem>(
      items: hasNextPage ? items.take(pageSize).toList() : items,
      pageIndex: pageIndex,
      pageSize: pageSize,
      hasNextPage: hasNextPage,
    );
  }

  Future<IntercessoryPrayerItem> addIntercessoryPrayerByShareId(
    String shareId,
  ) async {
    final rows = await _client.rpc(
      'add_intercessory_prayer_by_share_id',
      params: {'p_share_id': shareId},
    );
    final items = (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map<IntercessoryPrayerItem>(IntercessoryPrayerItem.fromMap)
        .toList(growable: false);
    if (items.isEmpty) {
      throw StateError('공유할 기도제목을 찾지 못했습니다.');
    }
    return items.first;
  }

  Future<void> deleteIntercessoryPrayer(String prayerLinkId) {
    return _client
        .from('user_intercessory_prayers')
        .delete()
        .eq('id', prayerLinkId);
  }

  Future<List<CharacterStudyProgress>> fetchCharacterStudyProgress({
    required String userId,
    required List<Character> people,
  }) async {
    final progressRows = await _client
        .from('user_event_progress')
        .select('event_id, is_bible_read, is_quiz_completed, is_completed')
        .eq('user_id', userId);
    final emotionRows = await _client
        .from('user_event_emotion_marks')
        .select('event_id')
        .eq('user_id', userId);
    final emotionIdSet = emotionRows
        .map((row) => row['event_id'] as String)
        .toSet();
    final completedIdSet = progressRows
        .where(
          (row) =>
              ((row['is_completed'] as bool?) ?? false) ||
              ((row['is_quiz_completed'] as bool?) ?? false),
        )
        .map((row) => row['event_id'] as String)
        .toSet();
    completedIdSet.addAll(emotionIdSet);

    final rows = await _client
        .from('events_ordered')
        .select('id, character_codes')
        .order('global_rank', ascending: true);

    final totalByCharacterCode = <String, Set<String>>{};
    final completedByCharacterCode = <String, Set<String>>{};
    for (final row in rows) {
      final eventId = row['id'] as String;
      final codes = row['character_codes'];
      if (codes is! List) {
        continue;
      }
      for (final code in codes.whereType<String>()) {
        totalByCharacterCode.putIfAbsent(code, () => <String>{}).add(eventId);
        if (completedIdSet.contains(eventId)) {
          completedByCharacterCode
              .putIfAbsent(code, () => <String>{})
              .add(eventId);
        }
      }
    }

    return people
        .map(
          (character) => CharacterStudyProgress(
            character: character,
            completedCount:
                completedByCharacterCode[character.code]?.length ?? 0,
            totalCount: totalByCharacterCode[character.code]?.length ?? 0,
          ),
        )
        .toList(growable: false);
  }

  Future<AppUserProfile?> _fetchProfileOrNull(String userId) async {
    final row = await _client
        .from('user_profiles')
        .select(
          'user_id, share_id, nickname, photo_url, prayer_request, created_at, updated_at',
        )
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) {
      return null;
    }
    return AppUserProfile.fromMap(row);
  }

  String _deriveNickname(User user, String? nicknameHint) {
    final cleanedHint = _cleanNullableText(nicknameHint);
    if (cleanedHint != null) {
      return cleanedHint;
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    for (final key in const ['full_name', 'name', 'nickname']) {
      final value = _cleanNullableText(metadata[key] as String?);
      if (value != null) {
        return value;
      }
    }

    final email = _cleanNullableText(user.email);
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }
    return '사용자';
  }

  String? _cleanNullableText(String? value) => cleanNullableText(value);

  String _normalizeExtension(String raw) => normalizeImageExtension(raw);

  String _contentTypeForExtension(String extension) =>
      contentTypeForImageExtension(extension);
}

/// 공백만 있거나 null인 문자열을 null로 정규화한다.
@visibleForTesting
String? cleanNullableText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// 이미지 확장자를 지원 값(jpg/webp/png 중 하나)으로 정규화한다.
/// jpeg/JPG 같은 변종도 jpg로, 미지원 확장자는 png로 폴백한다.
@visibleForTesting
String normalizeImageExtension(String raw) {
  final normalized = raw.toLowerCase().replaceAll('.', '');
  switch (normalized) {
    case 'jpg':
    case 'jpeg':
      return 'jpg';
    case 'webp':
      return 'webp';
    default:
      return 'png';
  }
}

/// 확장자에 대응하는 MIME 타입을 반환한다.
@visibleForTesting
String contentTypeForImageExtension(String extension) {
  switch (extension) {
    case 'jpg':
      return 'image/jpeg';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/png';
  }
}

@visibleForTesting
String normalizeCompanionDiaryTitle(String title) {
  final trimmed = title.trim();
  if (trimmed.length <= UserRepository.companionDiaryTitleMaxLength) {
    return trimmed;
  }
  return trimmed.substring(0, UserRepository.companionDiaryTitleMaxLength);
}

@visibleForTesting
String normalizeCompanionDiaryBody(String body) {
  final trimmed = body.trim();
  if (trimmed.length <= UserRepository.companionDiaryBodyMaxLength) {
    return trimmed;
  }
  return trimmed.substring(0, UserRepository.companionDiaryBodyMaxLength);
}

@visibleForTesting
String companionDiaryDateKey(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  final month = normalized.month.toString().padLeft(2, '0');
  final day = normalized.day.toString().padLeft(2, '0');
  return '${normalized.year}-$month-$day';
}
