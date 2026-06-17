import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/messenger_models.dart';
import '../../services/browser_speech_recognizer.dart';
import '../../services/briefing_speaker.dart';
import '../../services/external_calendar_service.dart';
import '../../services/holiday_calendar.dart';
import '../../services/messenger_backend.dart';

const _kInk = Color(0xFF111111);
const _kMuted = Color(0xFF8E8E93);
const _kSoft = Color(0xFFF3F5F4);
const _kAccentGreen = Color(0xFF00A86B);
const _kDarkGreen = Color(0xFF006B45);

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _recorder = AudioRecorder();
  final _speechRecognizer = BrowserSpeechRecognizer();
  final _stopwatch = Stopwatch();
  late DateTime _visibleMonth;
  late DateTime _selectedDay;
  late HolidayCountry _holidayCountry;
  Timer? _timer;
  var _recording = false;
  var _busy = false;
  var _freeSttActive = false;
  var _liveTranscript = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _holidayCountry = HolidayCountry.fromCode(widget.user.holidayCountryCode);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _speechRecognizer.cancel();
    unawaited(BriefingSpeaker.stop());
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = BackendScope.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFDFF9EA),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8FFF1), Color(0xFF0BB273)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _CalendarHeader(
                title: '일정',
                onBack: () => Navigator.of(context).maybePop(),
                onSettings: () => _showNotificationSettings(widget.user),
              ),
              Expanded(
                child: StreamBuilder<List<CalendarEvent>>(
                  stream: backend.watchCalendarEvents(widget.user.uid),
                  builder: (context, snapshot) {
                    final events = _visibleEvents(
                      snapshot.data ?? const <CalendarEvent>[],
                    );
                    final nextEvent = _nextUpcomingEvent(events);
                    final selectedEvents = _eventsForDay(events, _selectedDay);
                    final selectedHolidays = HolidayCalendar.holidaysForDay(
                      _holidayCountry,
                      _selectedDay,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (nextEvent != null)
                          _NextUpcomingEventCard(
                            event: nextEvent,
                            onTap: () => _showEventSheet(event: nextEvent),
                          ),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            margin: EdgeInsets.fromLTRB(
                              14,
                              nextEvent == null ? 8 : 0,
                              14,
                              14,
                            ),
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 28,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: _CalendarBody(
                              snapshot: snapshot,
                              events: events,
                              selectedDay: _selectedDay,
                              selectedEvents: selectedEvents,
                              selectedHolidays: selectedHolidays,
                              visibleMonth: _visibleMonth,
                              holidayCountry: _holidayCountry,
                              onRetry: () => setState(() {}),
                              onPreviousMonth: _showPreviousMonth,
                              onNextMonth: _showNextMonth,
                              onToday: _showCurrentMonth,
                              onSearch: () => _showCalendarSearch(events),
                              onSelectDay: (day) {
                                setState(() {
                                  _selectedDay = day;
                                  _visibleMonth = DateTime(day.year, day.month);
                                });
                              },
                              onOpenEvent: (event) =>
                                  _showEventSheet(event: event),
                              onBriefing: () => _playTodayBriefing(events),
                              recording: _recording,
                              busy: _busy,
                              elapsed: _stopwatch.elapsed,
                              onVoice: _toggleRecording,
                              onManual: () =>
                                  _showEventSheet(initialDate: _selectedDay),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<CalendarEvent> _visibleEvents(List<CalendarEvent> events) {
    final visible = events
        .where((event) => event.status == 'active')
        .toList(growable: false);
    visible.sort((a, b) => a.startAt.compareTo(b.startAt));
    return visible;
  }

  CalendarEvent? _nextUpcomingEvent(List<CalendarEvent> events) {
    final now = DateTime.now();
    for (final event in events) {
      if (event.startAt.isAfter(now) || event.endAt.isAfter(now)) {
        return event;
      }
    }
    return null;
  }

  List<CalendarEvent> _eventsForDay(List<CalendarEvent> events, DateTime day) {
    return events
        .where((event) => _isSameDay(event.startAt, day))
        .toList(growable: false);
  }

  void _showPreviousMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
      _selectedDay = DateTime(_visibleMonth.year, _visibleMonth.month);
    });
  }

  void _showNextMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
      _selectedDay = DateTime(_visibleMonth.year, _visibleMonth.month);
    });
  }

  void _showCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  Future<void> _showEventSheet({
    CalendarIntentDraft? draft,
    CalendarEvent? event,
    DateTime? initialDate,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CalendarEventSheet(
        draft: draft,
        event: event,
        initialDate: initialDate,
      ),
    );
  }

  Future<void> _showCalendarSearch(List<CalendarEvent> events) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => _CalendarSearchSheet(
        events: events,
        onOpenEvent: (event) => _showEventSheet(event: event),
      ),
    );
  }

  Future<void> _showNotificationSettings(AppUser user) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CalendarNotificationSettingsSheet(
        user: user,
        initialHolidayCountry: _holidayCountry,
        onHolidayCountryChanged: (country) {
          if (mounted) {
            setState(() => _holidayCountry = country);
          }
        },
      ),
    );
  }

  Future<void> _playTodayBriefing(List<CalendarEvent> events) async {
    final text = _todayBriefingText(events);
    final messenger = ScaffoldMessenger.of(context);
    final spoken = await BriefingSpeaker.speak(text);
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(spoken ? '오늘 일정 브리핑을 재생합니다.' : text),
        duration: Duration(seconds: spoken ? 2 : 5),
      ),
    );
  }

  String _todayBriefingText(List<CalendarEvent> events) {
    final today = DateTime.now();
    final todayEvents = _eventsForDay(events, today)
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final todayHolidays = HolidayCalendar.holidaysForDay(
      _holidayCountry,
      today,
    );
    final label =
        '${today.month}월 ${today.day}일 ${_weekdayName(today.weekday)}';
    if (todayEvents.isEmpty && todayHolidays.isEmpty) {
      return '좋은 아침입니다. 오늘 $label 등록된 일정은 없습니다.';
    }
    final buffer = StringBuffer('좋은 아침입니다. 오늘 $label ');
    if (todayHolidays.isNotEmpty) {
      buffer.write(
        '공휴일은 ${todayHolidays.map((holiday) => holiday.title).join(', ')}입니다. ',
      );
    }
    buffer.write('일정은 총 ${todayEvents.length}개입니다. ');
    for (final event in todayEvents) {
      buffer.write('${_briefingTime(event.startAt)}에 ${event.title}. ');
    }
    return buffer.toString().trim();
  }

  Future<void> _toggleRecording() async {
    if (_busy) {
      return;
    }
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    await _run(() async {
      final permitted = await _recorder.hasPermission();
      if (!permitted) {
        throw StateError('마이크 권한이 필요합니다.');
      }
      _freeSttActive = false;
      _liveTranscript = '';
      if (BrowserSpeechRecognizer.enabled) {
        try {
          await _speechRecognizer.start(
            onTranscript: (transcript) {
              _liveTranscript = transcript;
            },
          );
          _freeSttActive = true;
        } catch (_) {
          _freeSttActive = false;
          await _speechRecognizer.cancel();
        }
      }
      final encoder = await _preferredEncoder();
      final path = await _recordingPath(encoder);
      try {
        await _recorder.start(_voiceRecordConfig(encoder), path: path);
      } catch (_) {
        await _speechRecognizer.cancel();
        rethrow;
      }
      _stopwatch
        ..reset()
        ..start();
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) {
          setState(() {});
        }
      });
      setState(() => _recording = true);
    }, keepBusy: false);
  }

  Future<void> _stopRecording() async {
    if (!_recording) {
      return;
    }
    final path = await _recorder.stop();
    final transcriptOverride = _freeSttActive
        ? await _speechRecognizer.stop()
        : null;
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();
    final durationMs = _stopwatch.elapsedMilliseconds;
    final liveTranscript = transcriptOverride?.trim().isNotEmpty == true
        ? transcriptOverride
        : _liveTranscript.trim();
    setState(() {
      _recording = false;
      _freeSttActive = false;
    });
    if (path == null || durationMs < 500) {
      _showError('녹음 시간이 너무 짧습니다.');
      return;
    }

    await _run(() async {
      final backend = BackendScope.of(context);
      var manualTranscript = liveTranscript?.trim();
      if (BrowserSpeechRecognizer.enabled &&
          (manualTranscript == null || manualTranscript.isEmpty)) {
        manualTranscript = await _showManualTranscriptSheet();
        if (manualTranscript == null || manualTranscript.trim().isEmpty) {
          return;
        }
      }
      final draft = await _createCalendarDraftWithRecovery(
        backend: backend,
        path: path,
        durationMs: durationMs,
        transcriptOverride: manualTranscript,
      );
      if (draft == null) {
        return;
      }
      if (!mounted) {
        return;
      }
      await _createVoiceEventFromDraft(draft);
    });
  }

  Future<void> _createVoiceEventFromDraft(CalendarIntentDraft draft) async {
    final title = draft.parsedTitle?.trim();
    final startAt = draft.startAt;
    final endAt = draft.endAt;
    if (!draft.isComplete ||
        title == null ||
        startAt == null ||
        endAt == null) {
      final message = '일정 제목, 날짜, 시간을 모두 인식하지 못했습니다. 다시 말해 주세요.';
      unawaited(BriefingSpeaker.speak(message));
      _showError(message);
      return;
    }

    final event = await BackendScope.of(context).createCalendarEvent(
      title: title,
      startAt: startAt,
      endAt: endAt,
      timezone: draft.timezone,
      source: 'voice',
      transcript: draft.transcript,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _visibleMonth = DateTime(event.startAt.year, event.startAt.month);
      _selectedDay = DateTime(
        event.startAt.year,
        event.startAt.month,
        event.startAt.day,
      );
    });

    final message = _eventAddedSpeechMessage(event);
    await BriefingSpeaker.speak(message);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<CalendarIntentDraft?> _createCalendarDraftWithRecovery({
    required MessengerBackend backend,
    required String path,
    required int durationMs,
    String? transcriptOverride,
  }) async {
    var manualTranscript = transcriptOverride?.trim();
    for (;;) {
      try {
        return await backend.createCalendarIntentDraft(
          audioFilePath: path,
          durationMs: durationMs,
          transcriptOverride: manualTranscript?.isNotEmpty == true
              ? manualTranscript
              : null,
        );
      } catch (error) {
        if (!_isRecoverableCalendarSttError(error)) {
          rethrow;
        }
        manualTranscript = await _showManualTranscriptSheet();
        if (manualTranscript == null || manualTranscript.trim().isEmpty) {
          return null;
        }
      }
    }
  }

  String _eventAddedSpeechMessage(CalendarEvent event) {
    final start = event.startAt;
    final period = start.hour < 12 ? '오전' : '오후';
    final hour = start.hour % 12 == 0 ? 12 : start.hour % 12;
    final minute = start.minute == 0 ? '' : ' ${start.minute}분';
    return '${start.month}월 ${start.day}일 $period $hour시$minute에 ${event.title} 일정이 추가되었습니다.';
  }

  bool _isRecoverableCalendarSttError(Object error) {
    final message = error.toString();
    return message.contains('STT 엔진') ||
        message.contains('STT engine') ||
        message.contains('Transcription failed') ||
        message.contains('transcription failed') ||
        message.contains('Calendar voice transcription failed') ||
        message.contains('DEEPGRAM_API_KEY');
  }

  Future<AudioEncoder> _preferredEncoder() async {
    final candidates = kIsWeb
        ? const [AudioEncoder.opus, AudioEncoder.wav]
        : defaultTargetPlatform == TargetPlatform.windows
        ? const [AudioEncoder.wav]
        : const [AudioEncoder.wav, AudioEncoder.aacLc];
    for (final candidate in candidates) {
      if (await _recorder.isEncoderSupported(candidate)) {
        return candidate;
      }
    }
    return AudioEncoder.wav;
  }

  RecordConfig _voiceRecordConfig(AudioEncoder encoder) {
    return RecordConfig(
      encoder: encoder,
      bitRate: 64000,
      sampleRate: 16000,
      numChannels: 1,
      androidConfig: const AndroidRecordConfig(
        audioSource: AndroidAudioSource.mic,
      ),
    );
  }

  Future<String> _recordingPath(AudioEncoder encoder) async {
    if (kIsWeb) {
      return '';
    }
    final tempDir = await getTemporaryDirectory();
    final extension = encoder == AudioEncoder.wav ? 'wav' : 'm4a';
    return '${tempDir.path}/calendar_${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  Future<String?> _showManualTranscriptSheet() {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '음성을 인식하지 못했습니다',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                decoration: _inputDecoration(
                  '변환 텍스트',
                  '올해 7월 3일 오후 2시에 회의라는 일정 추가해줘',
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(controller.text.trim()),
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccentGreen,
                  foregroundColor: Colors.white,
                ),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _run(
    Future<void> Function() action, {
    bool keepBusy = true,
  }) async {
    if (_busy && keepBusy) {
      return;
    }
    if (keepBusy) {
      setState(() => _busy = true);
    }
    try {
      await action();
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted && keepBusy) {
        setState(() => _busy = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.title,
    required this.onBack,
    required this.onSettings,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '뒤로',
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left_rounded, size: 32),
          ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _kInk,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: '알림 설정',
            onPressed: onSettings,
            icon: const Icon(Icons.notifications_active_rounded, size: 26),
          ),
        ],
      ),
    );
  }
}

class _NextUpcomingEventCard extends StatelessWidget {
  const _NextUpcomingEventCard({required this.event, required this.onTap});

  final CalendarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
              boxShadow: [
                BoxShadow(
                  color: _kDarkGreen.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF44D6A0), Color(0xFF00A86B)],
                    ),
                  ),
                  child: const Icon(
                    Icons.event_available_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '다가오는 일정',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _kDarkGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _kInk,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      DateFormat('M/d').format(event.startAt),
                      style: const TextStyle(
                        color: _kInk,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('HH:mm').format(event.startAt),
                      style: const TextStyle(
                        color: _kMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: _kMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarBody extends StatelessWidget {
  const _CalendarBody({
    required this.snapshot,
    required this.events,
    required this.selectedDay,
    required this.selectedEvents,
    required this.selectedHolidays,
    required this.visibleMonth,
    required this.holidayCountry,
    required this.onRetry,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
    required this.onSearch,
    required this.onSelectDay,
    required this.onOpenEvent,
    required this.onBriefing,
    required this.recording,
    required this.busy,
    required this.elapsed,
    required this.onVoice,
    required this.onManual,
  });

  final AsyncSnapshot<List<CalendarEvent>> snapshot;
  final List<CalendarEvent> events;
  final DateTime selectedDay;
  final List<CalendarEvent> selectedEvents;
  final List<CalendarHoliday> selectedHolidays;
  final DateTime visibleMonth;
  final HolidayCountry holidayCountry;
  final VoidCallback onRetry;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;
  final VoidCallback onSearch;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<CalendarEvent> onOpenEvent;
  final VoidCallback onBriefing;
  final bool recording;
  final bool busy;
  final Duration elapsed;
  final VoidCallback onVoice;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    if (snapshot.hasError) {
      return _CalendarError(
        message: '일정을 불러오지 못했습니다.',
        detail: snapshot.error.toString(),
        onRetry: onRetry,
      );
    }
    if (snapshot.connectionState == ConnectionState.waiting && events.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _MonthCalendar(
            month: visibleMonth,
            selectedDay: selectedDay,
            events: events,
            holidayCountry: holidayCountry,
            onPreviousMonth: onPreviousMonth,
            onNextMonth: onNextMonth,
            onToday: onToday,
            onSearch: onSearch,
            onSelectDay: onSelectDay,
            onOpenEvent: onOpenEvent,
          ),
        ),
        const SizedBox(height: 12),
        _SelectedDayAgenda(
          day: selectedDay,
          events: selectedEvents,
          holidays: selectedHolidays,
          onOpenEvent: onOpenEvent,
          onBriefing: onBriefing,
        ),
        const SizedBox(height: 12),
        _CalendarActions(
          recording: recording,
          busy: busy,
          elapsed: elapsed,
          onVoice: onVoice,
          onManual: onManual,
        ),
      ],
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.selectedDay,
    required this.events,
    required this.holidayCountry,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
    required this.onSearch,
    required this.onSelectDay,
    required this.onOpenEvent,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<CalendarEvent> events;
  final HolidayCountry holidayCountry;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;
  final VoidCallback onSearch;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<CalendarEvent> onOpenEvent;

  @override
  Widget build(BuildContext context) {
    final monthEvents = events
        .where((event) => _isSameMonth(event.startAt, month))
        .toList(growable: false);
    final days = _calendarDays(month);
    final holidays = HolidayCalendar.holidaysForRange(
      holidayCountry,
      days.first,
      days.last,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MonthToolbar(
          month: month,
          eventCount: monthEvents.length,
          onPreviousMonth: onPreviousMonth,
          onNextMonth: onNextMonth,
          onToday: onToday,
          onSearch: onSearch,
        ),
        const SizedBox(height: 12),
        const _WeekdayHeader(),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const rowSpacing = 5.0;
              final rowHeight = ((constraints.maxHeight - rowSpacing * 5) / 6)
                  .clamp(62.0, 96.0);
              return GridView.builder(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: rowHeight,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: rowSpacing,
                ),
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final day = days[index];
                  final dayEvents = events
                      .where((event) => _isSameDay(event.startAt, day))
                      .toList(growable: false);
                  final dayHolidays = holidays
                      .where((holiday) => _isSameDay(holiday.date, day))
                      .toList(growable: false);
                  return _MonthDayCell(
                    day: day,
                    currentMonth: _isSameMonth(day, month),
                    selected: _isSameDay(day, selectedDay),
                    today: _isSameDay(day, DateTime.now()),
                    events: dayEvents,
                    holidays: dayHolidays,
                    onTap: () => onSelectDay(day),
                    onOpenEvent: onOpenEvent,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MonthToolbar extends StatelessWidget {
  const _MonthToolbar({
    required this.month,
    required this.eventCount,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
    required this.onSearch,
  });

  final DateTime month;
  final int eventCount;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '이전 달',
          onPressed: onPreviousMonth,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('M월').format(month),
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '${month.year} · $eventCount개 일정',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _kMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onToday,
          style: TextButton.styleFrom(
            foregroundColor: _kDarkGreen,
            minimumSize: const Size(58, 40),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          child: const Text('오늘'),
        ),
        IconButton(
          tooltip: '검색',
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton(
          tooltip: '다음 달',
          onPressed: onNextMonth,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    const labels = ['월', '화', '수', '목', '금', '토', '일'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: label == '일' ? const Color(0xFFFF3040) : _kMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.day,
    required this.currentMonth,
    required this.selected,
    required this.today,
    required this.events,
    required this.holidays,
    required this.onTap,
    required this.onOpenEvent,
  });

  final DateTime day;
  final bool currentMonth;
  final bool selected;
  final bool today;
  final List<CalendarEvent> events;
  final List<CalendarHoliday> holidays;
  final VoidCallback onTap;
  final ValueChanged<CalendarEvent> onOpenEvent;

  @override
  Widget build(BuildContext context) {
    final visibleHolidays = holidays.take(1).toList(growable: false);
    final visibleEventLimit = visibleHolidays.isEmpty ? 2 : 1;
    final visibleEvents = events
        .take(visibleEventLimit)
        .toList(growable: false);
    final moreCount =
        (events.length - visibleEvents.length) +
        (holidays.length - visibleHolidays.length);
    final hasHoliday = holidays.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFE1FFF0)
                : today
                ? const Color(0xFFF2FFF8)
                : Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? _kAccentGreen : const Color(0xFFECEFED),
              width: selected ? 1.4 : 0.7,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    constraints: const BoxConstraints(
                      minWidth: 19,
                      minHeight: 19,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: today
                        ? const BoxDecoration(
                            color: _kAccentGreen,
                            shape: BoxShape.circle,
                          )
                        : null,
                    alignment: Alignment.center,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        color: today
                            ? Colors.white
                            : hasHoliday && currentMonth
                            ? const Color(0xFFFF3040)
                            : currentMonth
                            ? _kInk
                            : const Color(0xFFC6C8CC),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (events.isNotEmpty || holidays.isNotEmpty)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: hasHoliday
                            ? const Color(0xFFFF3040)
                            : selected
                            ? _kDarkGreen
                            : _kAccentGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 3),
                    for (final holiday in visibleHolidays) ...[
                      _HolidayChip(holiday: holiday),
                      if (visibleEvents.isNotEmpty) const SizedBox(height: 2),
                    ],
                    for (
                      var index = 0;
                      index < visibleEvents.length;
                      index++
                    ) ...[
                      _CalendarChip(
                        event: visibleEvents[index],
                        color: _chipColor(index),
                        onTap: () => onOpenEvent(visibleEvents[index]),
                      ),
                      if (index != visibleEvents.length - 1)
                        const SizedBox(height: 2),
                    ],
                    if (moreCount > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '+$moreCount',
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _kDarkGreen,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarChip extends StatelessWidget {
  const _CalendarChip({
    required this.event,
    required this.color,
    required this.onTap,
  });

  final CalendarEvent event;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 15,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          event.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _HolidayChip extends StatelessWidget {
  const _HolidayChip({required this.holiday});

  final CalendarHoliday holiday;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 15,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B6B),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        holiday.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _SelectedDayAgenda extends StatelessWidget {
  const _SelectedDayAgenda({
    required this.day,
    required this.events,
    required this.holidays,
    required this.onOpenEvent,
    required this.onBriefing,
  });

  final DateTime day;
  final List<CalendarEvent> events;
  final List<CalendarHoliday> holidays;
  final ValueChanged<CalendarEvent> onOpenEvent;
  final VoidCallback onBriefing;

  @override
  Widget build(BuildContext context) {
    final label = '${day.month}월 ${day.day}일 ${_weekdayName(day.weekday)}';
    final rows = holidays.length + events.length;
    return Container(
      constraints: const BoxConstraints(minHeight: 86, maxHeight: 158),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8F7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _kInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onBriefing,
                style: TextButton.styleFrom(
                  foregroundColor: _kDarkGreen,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.volume_up_rounded, size: 16),
                label: const Text(
                  '브리핑',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows == 0)
            const Text(
              '등록된 일정이 없습니다',
              style: TextStyle(
                color: _kMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: rows,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  if (index < holidays.length) {
                    return _HolidayAgendaRow(holiday: holidays[index]);
                  }
                  final event = events[index - holidays.length];
                  return _AgendaRow(
                    event: event,
                    onTap: () => onOpenEvent(event),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({required this.event, required this.onTap});

  final CalendarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: _kAccentGreen,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              DateFormat('HH:mm').format(event.startAt),
              style: const TextStyle(
                color: _kMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _kInk,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HolidayAgendaRow extends StatelessWidget {
  const _HolidayAgendaRow({required this.holiday});

  final CalendarHoliday holiday;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFFF3040),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.flag_rounded, size: 14, color: Color(0xFFFF3040)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${holiday.title} · ${holiday.countryLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kInk,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarNotificationSettingsSheet extends StatefulWidget {
  const _CalendarNotificationSettingsSheet({
    required this.user,
    required this.initialHolidayCountry,
    required this.onHolidayCountryChanged,
  });

  final AppUser user;
  final HolidayCountry initialHolidayCountry;
  final ValueChanged<HolidayCountry> onHolidayCountryChanged;

  @override
  State<_CalendarNotificationSettingsSheet> createState() =>
      _CalendarNotificationSettingsSheetState();
}

class _CalendarNotificationSettingsSheetState
    extends State<_CalendarNotificationSettingsSheet> {
  static const _leadOptions = [0, 5, 10, 30, 60, 120, 1440];
  static const _briefingOptions = [420, 480, 540];

  late bool _reminderEnabled;
  late int _leadMinutes;
  late bool _briefingEnabled;
  late int _briefingMinuteOfDay;
  late HolidayCountry _holidayCountry;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _reminderEnabled = widget.user.calendarReminderEnabled;
    _leadMinutes = _normalizeLead(widget.user.calendarReminderLeadMinutes);
    _briefingEnabled = widget.user.morningBriefingEnabled;
    _briefingMinuteOfDay = _normalizeBriefingTime(
      widget.user.morningBriefingMinuteOfDay,
    );
    _holidayCountry = widget.initialHolidayCountry;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1E4E2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '일정 알림',
              style: TextStyle(
                color: _kInk,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              value: _reminderEnabled,
              activeThumbColor: _kAccentGreen,
              activeTrackColor: const Color(0xFFD7F7E8),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '일정 시작 전 미리 알림',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(_leadLabel(_leadMinutes)),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _reminderEnabled = value),
            ),
            DropdownButtonFormField<int>(
              initialValue: _leadMinutes,
              decoration: _inputDecoration('미리 알림 시간', ''),
              items: [
                for (final value in _leadOptions)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_leadLabel(value)),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _leadMinutes = value);
                      }
                    },
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              value: _briefingEnabled,
              activeThumbColor: _kAccentGreen,
              activeTrackColor: const Color(0xFFD7F7E8),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '아침 음성 브리핑',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('${_minuteLabel(_briefingMinuteOfDay)}에 알림'),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _briefingEnabled = value),
            ),
            DropdownButtonFormField<int>(
              initialValue: _briefingMinuteOfDay,
              decoration: _inputDecoration('브리핑 시간', ''),
              items: [
                for (final value in _briefingOptions)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_minuteLabel(value)),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _briefingMinuteOfDay = value);
                      }
                    },
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 12),
            DropdownButtonFormField<HolidayCountry>(
              initialValue: _holidayCountry,
              decoration: _inputDecoration('공휴일 국가', '월간 캘린더에 표시할 국가'),
              items: [
                for (final country in HolidayCountry.values)
                  DropdownMenuItem(value: country, child: Text(country.label)),
              ],
              onChanged: _saving
                  ? null
                  : (country) {
                      if (country != null) {
                        setState(() => _holidayCountry = country);
                      }
                    },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: _kAccentGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(
                _saving ? '저장 중...' : '저장',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await BackendScope.of(context).updateCalendarNotificationSettings(
        calendarReminderEnabled: _reminderEnabled,
        calendarReminderLeadMinutes: _leadMinutes,
        morningBriefingEnabled: _briefingEnabled,
        morningBriefingMinuteOfDay: _briefingMinuteOfDay,
        timezone: widget.user.calendarTimezone,
        holidayCountryCode: _holidayCountry.code,
      );
      if (!mounted) {
        return;
      }
      widget.onHolidayCountryChanged(_holidayCountry);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('일정 알림 설정을 저장했습니다.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  int _normalizeLead(int value) {
    return _leadOptions.contains(value) ? value : 30;
  }

  int _normalizeBriefingTime(int value) {
    return _briefingOptions.contains(value) ? value : 480;
  }
}

class _CalendarSearchSheet extends StatefulWidget {
  const _CalendarSearchSheet({required this.events, required this.onOpenEvent});

  final List<CalendarEvent> events;
  final ValueChanged<CalendarEvent> onOpenEvent;

  @override
  State<_CalendarSearchSheet> createState() => _CalendarSearchSheetState();
}

class _CalendarSearchSheetState extends State<_CalendarSearchSheet> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final events = widget.events
        .where((event) => _matchesCalendarQuery(event, query))
        .toList(growable: false);
    return FractionallySizedBox(
      heightFactor: 0.78,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '일정 검색',
              style: TextStyle(
                color: _kInk,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: _inputDecoration('검색어', '제목, 날짜, 상세 내용, 음성 텍스트'),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: events.isEmpty
                  ? const Center(
                      child: Text(
                        '검색 결과가 없습니다',
                        style: TextStyle(
                          color: _kMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: events.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        return _SearchResultTile(
                          event: event,
                          onTap: () {
                            Navigator.of(context).pop();
                            Future<void>.microtask(
                              () => widget.onOpenEvent(event),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.event, required this.onTap});

  final CalendarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8F7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: _kAccentGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kInk,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${DateFormat('M월 d일 HH:mm').format(event.startAt)} · ${event.durationMinutes}분',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<DateTime> _calendarDays(DateTime month) {
  final first = DateTime(month.year, month.month);
  final leading = first.weekday - DateTime.monday;
  final start = first.subtract(Duration(days: leading));
  return List<DateTime>.generate(
    42,
    (index) => start.add(Duration(days: index)),
  );
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isSameMonth(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month;
}

String _weekdayName(int weekday) {
  const names = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
  return names[(weekday - 1).clamp(0, 6)];
}

String _briefingTime(DateTime value) {
  final hour = value.hour;
  final minute = value.minute;
  final period = hour < 12 ? '오전' : '오후';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  if (minute == 0) {
    return '$period $displayHour시';
  }
  return '$period $displayHour시 $minute분';
}

String _leadLabel(int minutes) {
  if (minutes <= 0) {
    return '시작 시간';
  }
  if (minutes == 1440) {
    return '하루 전';
  }
  if (minutes >= 60) {
    return '${minutes ~/ 60}시간 전';
  }
  return '$minutes분 전';
}

String _minuteLabel(int minuteOfDay) {
  final hour = (minuteOfDay ~/ 60).clamp(0, 23).toInt();
  final minute = (minuteOfDay % 60).clamp(0, 59).toInt();
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

bool _matchesCalendarQuery(CalendarEvent event, String query) {
  if (query.isEmpty) {
    return true;
  }
  final normalized = query.toLowerCase();
  final date = DateFormat('yyyy-MM-dd HH:mm M월 d일').format(event.startAt);
  return event.title.toLowerCase().contains(normalized) ||
      event.details.toLowerCase().contains(normalized) ||
      event.transcript.toLowerCase().contains(normalized) ||
      date.toLowerCase().contains(normalized);
}

Color _chipColor(int index) {
  const colors = [
    Color(0xFF00A86B),
    Color(0xFF2EC98F),
    Color(0xFF007C55),
    Color(0xFF5AD7A3),
  ];
  return colors[index % colors.length];
}

class _CalendarActions extends StatelessWidget {
  const _CalendarActions({
    required this.recording,
    required this.busy,
    required this.elapsed,
    required this.onVoice,
    required this.onManual,
  });

  final bool recording;
  final bool busy;
  final Duration elapsed;
  final VoidCallback onVoice;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final seconds = elapsed.inSeconds.toString().padLeft(2, '0');
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: busy ? null : onVoice,
            style: FilledButton.styleFrom(
              backgroundColor: recording ? _kDarkGreen : _kAccentGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded),
            label: Text(recording ? '저장할 음성 확인 0:$seconds' : '음성으로 추가'),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: '직접 추가',
          onPressed: busy ? null : onManual,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFE8FFF1),
            foregroundColor: _kDarkGreen,
            minimumSize: const Size.square(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          icon: const Icon(Icons.edit_calendar_rounded),
        ),
      ],
    );
  }
}

class CalendarEventSheet extends StatefulWidget {
  const CalendarEventSheet({
    this.draft,
    this.event,
    this.initialDate,
    super.key,
  });

  final CalendarIntentDraft? draft;
  final CalendarEvent? event;
  final DateTime? initialDate;

  @override
  State<CalendarEventSheet> createState() => _CalendarEventSheetState();
}

class _CalendarEventSheetState extends State<CalendarEventSheet> {
  static const _defaultDurationMinutes = 60;

  late final TextEditingController _titleController;
  late final TextEditingController _detailsController;
  late final TextEditingController _dateController;
  late final TextEditingController _timeController;
  late final int _durationMinutes;
  var _saving = false;
  String? _error;

  bool get _isEditing => widget.event != null;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    final draft = widget.draft;
    final initialDate = widget.initialDate;
    final startAt = event?.startAt ?? draft?.startAt;
    final dateSeed = startAt ?? initialDate;
    final draftDuration = draft?.startAt != null && draft?.endAt != null
        ? draft!.endAt!
              .difference(draft.startAt!)
              .inMinutes
              .clamp(1, 24 * 60)
              .toInt()
        : null;
    _durationMinutes =
        event?.durationMinutes ?? draftDuration ?? _defaultDurationMinutes;
    _titleController = TextEditingController(
      text: event?.title ?? draft?.parsedTitle ?? '',
    );
    _detailsController = TextEditingController(text: event?.details ?? '');
    _dateController = TextEditingController(
      text: dateSeed == null ? '' : DateFormat('yyyy-MM-dd').format(dateSeed),
    );
    _timeController = TextEditingController(
      text: startAt == null ? '' : DateFormat('HH:mm').format(startAt),
    );
    for (final controller in [
      _titleController,
      _detailsController,
      _dateController,
      _timeController,
    ]) {
      controller.addListener(() => setState(() => _error = null));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = !_saving && _formValueOrNull() != null;
    final viewInsetBottom = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final bottomPadding =
        20 + (viewInsetBottom > safeBottom ? viewInsetBottom : safeBottom);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? '일정 수정' : '일정 추가',
                    style: const TextStyle(
                      color: _kInk,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (_isEditing)
                  IconButton(
                    tooltip: '삭제',
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
            if (widget.draft?.transcript.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAFBF3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '변환 텍스트',
                      style: TextStyle(
                        color: _kMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.draft!.transcript,
                      style: const TextStyle(
                        color: _kInk,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              maxLength: 120,
              decoration: _inputDecoration('제목', '예: 회의, 병원 예약'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _detailsController,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 2,
              maxLines: 4,
              maxLength: 2000,
              decoration: _inputDecoration('상세 내용', '장소, 준비물, 메모를 입력하세요'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dateController,
                    keyboardType: TextInputType.datetime,
                    decoration: _inputDecoration('날짜', 'YYYY-MM-DD'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _timeController,
                    keyboardType: TextInputType.datetime,
                    decoration: _inputDecoration('시간', 'HH:MM'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFF3040),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: canSave ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: _kAccentGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                disabledBackgroundColor: const Color(0xFFD8D8D8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isEditing ? '수정' : '저장'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 10),
              _ExternalCalendarActions(
                event: widget.event!,
                busy: _saving,
                onError: (message) => setState(() => _error = message),
              ),
              const SizedBox(height: 10),
              _ShareCalendarEventAction(
                event: widget.event!,
                busy: _saving,
                onError: (message) => setState(() => _error = message),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _CalendarFormValue? _formValueOrNull() {
    final title = _titleController.text.trim();
    if (title.isEmpty || title.length > 120) {
      return null;
    }
    final details = _detailsController.text.trim();
    if (details.length > 2000) {
      return null;
    }
    final date = _dateController.text.trim();
    final time = _timeController.text.trim();
    final matchDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
    final matchTime = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
    if (matchDate == null || matchTime == null) {
      return null;
    }
    final year = int.tryParse(matchDate.group(1)!);
    final month = int.tryParse(matchDate.group(2)!);
    final day = int.tryParse(matchDate.group(3)!);
    final hour = int.tryParse(matchTime.group(1)!);
    final minute = int.tryParse(matchTime.group(2)!);
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        hour > 23 ||
        minute > 59) {
      return null;
    }
    final startAt = DateTime(year, month, day, hour, minute);
    if (startAt.year != year ||
        startAt.month != month ||
        startAt.day != day ||
        startAt.hour != hour ||
        startAt.minute != minute) {
      return null;
    }
    if (!startAt.isAfter(DateTime.now())) {
      return null;
    }
    return _CalendarFormValue(
      title: title,
      details: details,
      startAt: startAt,
      endAt: startAt.add(Duration(minutes: _durationMinutes)),
      durationMinutes: _durationMinutes,
    );
  }

  Future<void> _save() async {
    final value = _formValueOrNull();
    if (value == null) {
      setState(() => _error = '제목, 날짜, 시간 또는 상세 내용을 확인해 주세요.');
      return;
    }
    setState(() => _saving = true);
    try {
      final backend = BackendScope.of(context);
      if (_isEditing) {
        await backend.updateCalendarEvent(
          eventId: widget.event!.id,
          title: value.title,
          startAt: value.startAt,
          endAt: value.endAt,
          details: value.details,
        );
      } else {
        await backend.createCalendarEvent(
          title: value.title,
          startAt: value.startAt,
          endAt: value.endAt,
          details: value.details,
          source: widget.draft == null ? 'manual' : 'voice',
          transcript: widget.draft?.transcript ?? '',
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    try {
      await BackendScope.of(
        context,
      ).deleteCalendarEvent(eventId: widget.event!.id);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }
}

class _ExternalCalendarActions extends StatelessWidget {
  const _ExternalCalendarActions({
    required this.event,
    required this.busy,
    required this.onError,
  });

  final CalendarEvent event;
  final bool busy;
  final ValueChanged<String> onError;

  @override
  Widget build(BuildContext context) {
    final appleAvailable =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => _addExternalCalendar(
                    context,
                    ExternalCalendarTarget.google,
                  ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kDarkGreen,
              side: const BorderSide(color: Color(0xFFBFEEDB)),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: const Text(
              'Google',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: busy || !appleAvailable
                ? null
                : () => _addExternalCalendar(
                    context,
                    ExternalCalendarTarget.apple,
                  ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kDarkGreen,
              side: const BorderSide(color: Color(0xFFBFEEDB)),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.event_available_rounded, size: 18),
            label: const Text(
              'Apple',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addExternalCalendar(
    BuildContext context,
    ExternalCalendarTarget target,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ExternalCalendarService.addEvent(event, target: target);
    if (!context.mounted) {
      return;
    }
    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            target == ExternalCalendarTarget.google
                ? 'Google Calendar 추가 화면을 열었습니다.'
                : 'Apple Calendar 추가 화면을 열었습니다.',
          ),
        ),
      );
      return;
    }
    onError('이 기기에서 외부 캘린더를 열 수 없습니다.');
  }
}

class _ShareCalendarEventAction extends StatelessWidget {
  const _ShareCalendarEventAction({
    required this.event,
    required this.busy,
    required this.onError,
  });

  final CalendarEvent event;
  final bool busy;
  final ValueChanged<String> onError;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: busy ? null : () => _shareToRoom(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: _kDarkGreen,
        side: const BorderSide(color: Color(0xFFBFEEDB)),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
      label: const Text(
        '채팅방에 공유',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }

  Future<void> _shareToRoom(BuildContext context) async {
    final backend = BackendScope.of(context);
    final user = await backend.authState().first;
    if (!context.mounted) {
      return;
    }
    if (user == null) {
      onError('로그인 후 공유할 수 있습니다.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: StreamBuilder<List<ChatRoom>>(
            stream: backend.watchRooms(user.uid),
            builder: (context, snapshot) {
              final rooms = snapshot.data ?? const <ChatRoom>[];
              if (snapshot.connectionState == ConnectionState.waiting &&
                  rooms.isEmpty) {
                return const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (rooms.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('공유할 채팅방이 없습니다.'),
                );
              }
              return ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                children: [
                  const ListTile(
                    title: Text(
                      '채팅방에 공유',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  for (final room in rooms)
                    ListTile(
                      leading: const Icon(Icons.forum_outlined),
                      title: Text(room.title),
                      subtitle: Text(
                        '${DateFormat('M월 d일 HH:mm').format(event.startAt)} 일정 제안',
                      ),
                      onTap: () async {
                        try {
                          await backend.createCalendarProposal(
                            roomId: room.id,
                            title: event.title,
                            details: event.details,
                            candidates: [
                              CalendarProposalCandidate(
                                id: 'candidate_1',
                                startAt: event.startAt,
                                endAt: event.endAt,
                              ),
                            ],
                            source: 'manual',
                            transcript: event.transcript,
                          );
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('채팅방에 일정 제안을 공유했습니다.'),
                              ),
                            );
                          }
                        } catch (error) {
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                          onError(error.toString());
                        }
                      },
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _CalendarFormValue {
  const _CalendarFormValue({
    required this.title,
    required this.details,
    required this.startAt,
    required this.endAt,
    required this.durationMinutes,
  });

  final String title;
  final String details;
  final DateTime startAt;
  final DateTime endAt;
  final int durationMinutes;
}

class _CalendarError extends StatelessWidget {
  const _CalendarError({
    required this.message,
    required this.detail,
    required this.onRetry,
  });

  final String message;
  final String detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFFF3040)),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _kMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration(String label, String hint) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: _kSoft,
    counterText: '',
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _kAccentGreen, width: 1.4),
    ),
  );
}
