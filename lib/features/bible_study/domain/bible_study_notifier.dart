import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../data/models/bible_event_model.dart';
import '../data/models/book_model.dart';
import '../data/repositories/bible_study_repository.dart';

final bibleStudyRepositoryProvider = Provider<BibleStudyRepository>((ref) {
  return BibleStudyRepository(ref.watch(bibleSupabaseClientProvider));
});

final bibleStudyNotifierProvider =
    StateNotifierProvider<BibleStudyNotifier, BibleStudyState>((ref) {
      return BibleStudyNotifier(ref.watch(bibleStudyRepositoryProvider));
    });

class BibleStudyState {
  const BibleStudyState({
    this.testament = 'NT',
    this.books = const [],
    this.selectedBook,
    this.events = const [],
    this.selectedEventIdx = 0,
    this.currentVersePage = 0,
    this.isLoading = false,
    this.isDetailLoading = false,
    this.error,
  });

  final String testament;
  final List<Book> books;
  final Book? selectedBook;
  final List<BibleEvent> events;
  final int selectedEventIdx;
  final int currentVersePage;
  final bool isLoading;
  final bool isDetailLoading;
  final String? error;

  BibleEvent? get selectedEvent {
    if (events.isEmpty ||
        selectedEventIdx < 0 ||
        selectedEventIdx >= events.length) {
      return null;
    }
    return events[selectedEventIdx];
  }

  BibleStudyState copyWith({
    String? testament,
    List<Book>? books,
    Book? selectedBook,
    bool clearSelectedBook = false,
    List<BibleEvent>? events,
    int? selectedEventIdx,
    int? currentVersePage,
    bool? isLoading,
    bool? isDetailLoading,
    String? error,
    bool clearError = false,
  }) {
    return BibleStudyState(
      testament: testament ?? this.testament,
      books: books ?? this.books,
      selectedBook: clearSelectedBook
          ? null
          : selectedBook ?? this.selectedBook,
      events: events ?? this.events,
      selectedEventIdx: selectedEventIdx ?? this.selectedEventIdx,
      currentVersePage: currentVersePage ?? this.currentVersePage,
      isLoading: isLoading ?? this.isLoading,
      isDetailLoading: isDetailLoading ?? this.isDetailLoading,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class BibleStudyNotifier extends StateNotifier<BibleStudyState> {
  BibleStudyNotifier(this._repository) : super(const BibleStudyState()) {
    loadInitial();
  }

  final BibleStudyRepository _repository;
  int _detailRequestSerial = 0;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  Future<void> loadInitial() async {
    await selectTestament('NT');
  }

  Future<void> selectTestament(String t) async {
    final testament = t == 'OT' ? 'OT' : 'NT';
    state = state.copyWith(
      testament: testament,
      isLoading: true,
      clearError: true,
      events: const [],
      selectedEventIdx: 0,
      currentVersePage: 0,
      isDetailLoading: false,
    );

    try {
      final books = await _repository.getBooks(testament);
      final fallbackBook = books.isNotEmpty ? books.first : null;
      state = state.copyWith(
        books: books,
        selectedBook: fallbackBook,
        isLoading: false,
      );
      if (fallbackBook != null) {
        await selectBook(fallbackBook);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '책 목록을 불러오지 못했습니다: $e');
    }
  }

  Future<void> selectBook(Book book) async {
    state = state.copyWith(
      selectedBook: book,
      isLoading: true,
      clearError: true,
      events: const [],
      selectedEventIdx: 0,
      currentVersePage: 0,
      isDetailLoading: false,
    );

    try {
      final events = await _repository.getEvents(book.id, _userId);
      state = state.copyWith(
        events: events,
        selectedEventIdx: 0,
        currentVersePage: 0,
        isLoading: false,
      );
      if (events.isNotEmpty) {
        await _loadEventDetailForIndex(0);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '사건 목록을 불러오지 못했습니다: $e');
    }
  }

  Future<void> selectEvent(int idx) async {
    if (idx < 0 || idx >= state.events.length) {
      return;
    }
    if (idx == state.selectedEventIdx &&
        state.selectedEvent?.isDetailLoaded == true) {
      return;
    }
    state = state.copyWith(selectedEventIdx: idx, currentVersePage: 0);
    await _loadEventDetailForIndex(idx);
  }

  Future<void> moveEvent(int dir) async {
    if (state.events.isEmpty) {
      return;
    }
    final next = (state.selectedEventIdx + dir).clamp(
      0,
      state.events.length - 1,
    );
    if (next == state.selectedEventIdx) {
      return;
    }
    await selectEvent(next);
  }

  void prevVersePage() {
    if (state.currentVersePage <= 0) {
      return;
    }
    state = state.copyWith(currentVersePage: state.currentVersePage - 1);
  }

  void nextVersePage() {
    final event = state.selectedEvent;
    if (event == null) {
      return;
    }
    if (state.currentVersePage >= event.versePages.length - 1) {
      return;
    }
    state = state.copyWith(currentVersePage: state.currentVersePage + 1);
  }

  Future<void> toggleComplete() async {
    final event = state.selectedEvent;
    if (event == null) {
      return;
    }
    final next = !event.isCompleted;
    final updatedEvents = [...state.events];
    updatedEvents[state.selectedEventIdx] =
        updatedEvents[state.selectedEventIdx].copyWith(isCompleted: next);
    state = state.copyWith(events: updatedEvents);

    final userId = _userId;
    if (userId == null) {
      return;
    }

    try {
      await _repository.toggleProgress(event.id, userId, next);
    } catch (_) {
      final rollbackEvents = [...state.events];
      rollbackEvents[state.selectedEventIdx] =
          rollbackEvents[state.selectedEventIdx].copyWith(isCompleted: !next);
      state = state.copyWith(events: rollbackEvents);
    }
  }

  Future<void> _loadEventDetailForIndex(int idx) async {
    if (idx < 0 || idx >= state.events.length) {
      return;
    }
    final currentEvent = state.events[idx];
    if (currentEvent.isDetailLoaded) {
      return;
    }

    final requestSerial = ++_detailRequestSerial;
    state = state.copyWith(isDetailLoading: true, clearError: true);

    try {
      final detail = await _repository.getEventDetail(currentEvent.id, _userId);
      if (requestSerial != _detailRequestSerial) {
        return;
      }

      final updatedEvents = [...state.events];
      final targetIdx = updatedEvents.indexWhere(
        (event) => event.id == detail.id,
      );
      if (targetIdx == -1) {
        state = state.copyWith(isDetailLoading: false);
        return;
      }

      final keepLocalCompletion = _userId == null;
      updatedEvents[targetIdx] = detail.copyWith(
        isCompleted: keepLocalCompletion
            ? updatedEvents[targetIdx].isCompleted
            : detail.isCompleted,
        isDetailLoaded: true,
      );

      state = state.copyWith(
        events: updatedEvents,
        isDetailLoading: false,
        clearError: true,
      );
    } catch (e) {
      if (requestSerial != _detailRequestSerial) {
        return;
      }
      state = state.copyWith(
        isDetailLoading: false,
        error: '사건 상세를 불러오지 못했습니다: $e',
      );
    }
  }
}
