import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import '../models/bible_verse.dart';
import '../models/intercessory_prayer_item.dart';
import '../models/paged_result.dart';
import '../models/person.dart';
import '../models/person_study_progress.dart';
import '../models/saved_bible_verse.dart';
import '../models/user_note.dart';

class UserRepository {
  const UserRepository(this._client);

  static const profileImageBucket = 'profile-images';

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

    await recordAttendance(user.id);
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

  Future<void> recordAttendance(String userId, {DateTime? date}) {
    final day = _dateOnly(date ?? DateTime.now());
    return _insertDailyRowIgnoringDuplicate(
      table: 'user_daily_attendance',
      values: {
        'user_id': userId,
        'attended_on': day.toIso8601String().split('T').first,
      },
    );
  }

  Future<void> recordStudyDay(String userId, {DateTime? date}) {
    final day = _dateOnly(date ?? DateTime.now());
    return _insertDailyRowIgnoringDuplicate(
      table: 'user_daily_study',
      values: {
        'user_id': userId,
        'studied_on': day.toIso8601String().split('T').first,
      },
    );
  }

  Future<int> fetchAttendanceStreak(String userId) async {
    final rows = await _client
        .from('user_daily_attendance')
        .select('attended_on')
        .eq('user_id', userId)
        .order('attended_on', ascending: false)
        .limit(400);
    return _computeStreak(rows, 'attended_on');
  }

  Future<int> fetchStudyStreak(String userId) async {
    final rows = await _client
        .from('user_daily_study')
        .select('studied_on')
        .eq('user_id', userId)
        .order('studied_on', ascending: false)
        .limit(400);
    return _computeStreak(rows, 'studied_on');
  }

  Future<PagedResult<UserNote>> fetchUserNotesPage({
    required String userId,
    required int pageIndex,
    int pageSize = 10,
  }) async {
    final from = pageIndex * pageSize;
    final to = from + pageSize;
    final rows = await _client
        .from('user_notes')
        .select('id, user_id, title, content, created_at, updated_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .range(from, to);

    final notes = rows.map<UserNote>((row) => UserNote.fromMap(row)).toList();
    final hasNextPage = notes.length > pageSize;
    return PagedResult<UserNote>(
      items: hasNextPage ? notes.take(pageSize).toList() : notes,
      pageIndex: pageIndex,
      pageSize: pageSize,
      hasNextPage: hasNextPage,
    );
  }

  Future<UserNote> createUserNote({
    required String userId,
    required String title,
    required String content,
  }) async {
    final row = await _client
        .from('user_notes')
        .insert({
          'user_id': userId,
          'title': title.trim(),
          'content': content.trim(),
        })
        .select('id, user_id, title, content, created_at, updated_at')
        .single();
    return UserNote.fromMap(row);
  }

  Future<void> deleteUserNote(String noteId) async {
    final rows = await _client
        .from('user_notes')
        .delete()
        .eq('id', noteId)
        .select('id');
    if ((rows as List<dynamic>).isEmpty) {
      throw StateError('노트를 삭제하지 못했습니다.');
    }
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
        .select(
          'id, user_id, translation, book_no, book_name, chapter_no, verse_no, verse_text, created_at',
        )
        .eq('user_id', userId)
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

  Future<Set<String>> fetchSavedVerseKeys(String userId) async {
    final rows = await _client
        .from('user_saved_verses')
        .select('translation, book_no, chapter_no, verse_no')
        .eq('user_id', userId);

    return rows
        .map(
          (row) => SavedBibleVerse.buildVerseKey(
            translation: row['translation'] as String,
            bookNo: row['book_no'] as int,
            chapterNo: row['chapter_no'] as int,
            verseNo: row['verse_no'] as int,
          ),
        )
        .toSet();
  }

  Future<bool> toggleSavedVerse({
    required String userId,
    required BibleVerse verse,
  }) async {
    final existing = await _client
        .from('user_saved_verses')
        .select('id')
        .eq('user_id', userId)
        .eq('translation', verse.translation)
        .eq('book_no', verse.bookNo)
        .eq('chapter_no', verse.chapterNo)
        .eq('verse_no', verse.verseNo)
        .maybeSingle();

    if (existing != null) {
      await _client
          .from('user_saved_verses')
          .delete()
          .eq('id', existing['id'] as String);
      return false;
    }

    await _client.from('user_saved_verses').insert({
      'user_id': userId,
      'translation': verse.translation,
      'book_no': verse.bookNo,
      'book_name': verse.bookName,
      'chapter_no': verse.chapterNo,
      'verse_no': verse.verseNo,
      'verse_text': verse.verseText,
    });
    return true;
  }

  Future<void> deleteSavedVerse(String verseId) {
    return _client.from('user_saved_verses').delete().eq('id', verseId);
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

  Future<List<PersonStudyProgress>> fetchPersonStudyProgress({
    required String userId,
    required List<Person> people,
  }) async {
    final completedEventIds = await _client
        .from('user_event_progress')
        .select('event_id, is_completed')
        .eq('user_id', userId)
        .eq('is_completed', true);
    final completedIdSet = completedEventIds
        .map((row) => row['event_id'] as String)
        .toSet();

    final rows = await _client
        .from('events')
        .select('id, event_persons(person_id)')
        .order('time_sort_key', ascending: true);

    final totalByPerson = <String, Set<String>>{};
    final completedByPerson = <String, Set<String>>{};
    for (final row in rows) {
      final eventId = row['id'] as String;
      final personRows = row['event_persons'] as List<dynamic>? ?? const [];
      for (final personRow in personRows.whereType<Map<String, dynamic>>()) {
        final personId = personRow['person_id'] as String?;
        if (personId == null) {
          continue;
        }
        totalByPerson.putIfAbsent(personId, () => <String>{}).add(eventId);
        if (completedIdSet.contains(eventId)) {
          completedByPerson
              .putIfAbsent(personId, () => <String>{})
              .add(eventId);
        }
      }
    }

    return people
        .map(
          (person) => PersonStudyProgress(
            person: person,
            completedCount: completedByPerson[person.id]?.length ?? 0,
            totalCount: totalByPerson[person.id]?.length ?? 0,
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

  Future<void> _insertDailyRowIgnoringDuplicate({
    required String table,
    required Map<String, dynamic> values,
  }) async {
    try {
      await _client.from(table).insert(values);
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        return;
      }
      rethrow;
    }
  }

  String? _cleanNullableText(String? value) => cleanNullableText(value);

  String _normalizeExtension(String raw) => normalizeImageExtension(raw);

  String _contentTypeForExtension(String extension) =>
      contentTypeForImageExtension(extension);

  DateTime _dateOnly(DateTime dateTime) => dateOnly(dateTime);

  int _computeStreak(List<dynamic> rows, String key) =>
      computeDailyStreak(rows, key);
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

/// 시:분:초를 제외한 날짜만 보존해 동일 날짜 비교를 가능하게 한다.
@visibleForTesting
DateTime dateOnly(DateTime dateTime) {
  return DateTime(dateTime.year, dateTime.month, dateTime.day);
}

/// 출석/학습 연속일수 계산.
///
/// rows는 `{key: "YYYY-MM-DD"}` 형태를 가정하고, 오늘 또는 어제가 포함되어 있지
/// 않으면 연속이 끊긴 것으로 간주해 0을 반환한다. 중복 날짜는 1회로 집계된다.
@visibleForTesting
int computeDailyStreak(List<dynamic> rows, String key) {
  final uniqueDays =
      rows
          .map((row) => row[key] as String?)
          .whereType<String>()
          .map(DateTime.parse)
          .map(dateOnly)
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));

  if (uniqueDays.isEmpty) {
    return 0;
  }

  final today = dateOnly(DateTime.now());
  final yesterday = today.subtract(const Duration(days: 1));
  if (uniqueDays.first != today && uniqueDays.first != yesterday) {
    return 0;
  }

  var streak = 1;
  for (var i = 1; i < uniqueDays.length; i++) {
    final previous = uniqueDays[i - 1];
    final expected = previous.subtract(const Duration(days: 1));
    if (uniqueDays[i] != expected) {
      break;
    }
    streak += 1;
  }
  return streak;
}
