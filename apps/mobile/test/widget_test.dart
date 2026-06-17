import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbal/main.dart';
import 'package:verbal/src/models/messenger_models.dart';
import 'package:verbal/src/services/attachment_picker.dart';
import 'package:verbal/src/services/demo_backend.dart';
import 'package:verbal/src/services/handle_policy.dart';
import 'package:verbal/src/services/holiday_calendar.dart';
import 'package:verbal/src/services/location_picker.dart';

void main() {
  setUp(() {
    AttachmentPicker.debugPick = (kind) async {
      if (kind == AttachmentPickKind.image) {
        return PickedAttachment(
          fileName: 'sample-photo.png',
          mimeType: 'image/png',
          sizeBytes: 4,
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        );
      }
      return PickedAttachment(
        fileName: 'Verbal Brief.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 2480000,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );
    };
    LocationPicker.debugPick = () async {
      return const PickedLocation(
        latitude: 37.5665,
        longitude: 126.9780,
        accuracyMeters: 12,
      );
    };
  });

  tearDown(() {
    AttachmentPicker.debugPick = null;
    LocationPicker.debugPick = null;
  });

  Future<void> openHome(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(VerbalApp(backend: DemoMessengerBackend()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
  }

  Future<void> openChat(WidgetTester tester) async {
    await openHome(tester);
    await tester.tap(find.text('김민지'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSheetTile(WidgetTester tester, String text) async {
    final tile = find
        .ancestor(of: find.text(text), matching: find.byType(ListTile))
        .first;
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  Future<void> tapMoreMenuItem(WidgetTester tester, String text) async {
    await tester.tap(find.byTooltip('더 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> scrollChatToBottom(WidgetTester tester) async {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
  }

  test('demo voice transcript requires an enabled STT engine', () async {
    final backend = DemoMessengerBackend();
    await backend.signInDemo();

    await expectLater(
      backend.createTranscriptionDraft(audioFilePath: '', durationMs: 1200),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('STT 엔진이 연결되어 있지 않습니다'),
        ),
      ),
    );
  });

  test('handle policy allows language characters numbers and underscore', () {
    expect(validateHandle('민지Alexあア漢字_123'), isNull);
    expect(normalizeHandle('@Alex민지_1'), 'alex민지_1');
    expect(validateHandle('min.ji'), contains('한글, 영어, 일본어, 중국어, 숫자, _'));
    expect(validateHandle('min-ji'), contains('한글, 영어, 일본어, 중국어, 숫자, _'));
    expect(validateHandle('ab'), contains('3~30자'));
    expect(validateHandle('a' * 31), contains('3~30자'));
  });

  test('voice message display text exposes transcript or STT state', () {
    final processing = ChatMessage(
      id: 'voice-processing',
      senderId: 'me',
      kind: MessageKind.voice,
      text: '',
      transcript: '',
      audioPath: null,
      durationMs: 4200,
      sttStatus: SttStatus.processing,
      sendMode: SendMode.instant,
      createdAt: DateTime(2026),
    );
    expect(processing.displayText, '음성 변환 중...');

    final failed = processing.copyWith(sttStatus: SttStatus.failed);
    expect(failed.displayText, '음성 변환 실패');

    final completed = processing.copyWith(
      text: '오늘 오후에 이야기해요',
      transcript: '오늘 오후에 이야기해요',
      sttStatus: SttStatus.completed,
    );
    expect(completed.displayText, '오늘 오후에 이야기해요');

    final placeholder = processing.copyWith(
      text: '음성 메시지',
      transcript: '',
      sttStatus: SttStatus.completed,
      deliveryStatus: MessageDeliveryStatus.sent,
    );
    expect(placeholder.displayText, '음성 변환 실패');
  });

  test('holiday calendar returns country specific holidays', () {
    expect(
      HolidayCalendar.holidaysForDay(
        HolidayCountry.korea,
        DateTime(2026, 5, 5),
      ).single.title,
      '어린이날',
    );
    expect(
      HolidayCalendar.holidaysForDay(
        HolidayCountry.unitedStates,
        DateTime(2026, 7, 3),
      ).single.title,
      'Independence Day',
    );
    expect(
      HolidayCalendar.holidaysForDay(
        HolidayCountry.japan,
        DateTime(2026, 9, 22),
      ).single.title,
      '国民の休日',
    );
    expect(
      HolidayCalendar.holidaysForDay(
        HolidayCountry.china,
        DateTime(2026, 10, 1),
      ).single.title,
      '国庆节',
    );
  });

  testWidgets('demo mode opens the room list', (tester) async {
    await openHome(tester);

    expect(find.text('김민지'), findsOneWidget);
    expect(find.textContaining('오늘 저녁에 통화 가능해?'), findsOneWidget);
    expect(find.text('Your note'), findsOneWidget);
    expect(find.text('메시지'), findsOneWidget);
    expect(find.text('채널'), findsOneWidget);
    expect(find.text('요청'), findsNothing);
    expect(find.byTooltip('메뉴'), findsOneWidget);

    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();

    expect(find.text('요청함'), findsNothing);
    expect(find.text('계정/관계'), findsOneWidget);
    expect(find.text('대화/데이터'), findsOneWidget);
    expect(find.text('설정'), findsOneWidget);
    expect(find.text('안전/지원'), findsOneWidget);
    expect(find.text('정보/정책'), findsOneWidget);
    expect(find.text('계정 상태'), findsOneWidget);
    expect(find.text('내 프로필'), findsOneWidget);
    expect(find.text('친구/연락처'), findsOneWidget);
    expect(find.text('저장한 메시지'), findsOneWidget);
    expect(find.text('계정 관리'), findsOneWidget);
    expect(find.text('대화 백업 및 복원'), findsOneWidget);
    expect(find.text('권한 관리'), findsOneWidget);
    expect(find.text('알림 설정'), findsOneWidget);
    expect(find.text('개인정보 및 보안'), findsOneWidget);
    expect(find.text('데이터 및 저장 공간'), findsOneWidget);
    expect(find.text('언어'), findsOneWidget);
    expect(find.text('테마'), findsOneWidget);
    expect(find.text('안전센터'), findsOneWidget);
    expect(find.text('고객지원'), findsOneWidget);
    expect(find.text('공지사항'), findsOneWidget);
    expect(find.text('약관 및 정책'), findsOneWidget);
    expect(find.text('앱 정보'), findsOneWidget);
    expect(find.text('오픈소스 라이선스'), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('내 데이터 내보내기'), findsNothing);
    expect(find.text('내 데이터 다운로드'), findsNothing);
    expect(find.text('계정 삭제'), findsNothing);
    expect(find.text('운영 상태 확인'), findsNothing);

    await tapSheetTile(tester, '내 프로필');
    expect(
      find.byKey(const ValueKey('profile-display-name-field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('profile-handle-field')), findsOneWidget);
    expect(find.text('초대 링크/QR'), findsOneWidget);
    await tester.tap(find.text('초대 링크/QR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('verbal.local/profile/demo'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-display-name-field')),
      'Demo Renamed',
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-handle-field')),
      'demo_next',
    );
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('demo_next'), findsOneWidget);

    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '친구/연락처');
    expect(find.text('초대 링크/QR'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '계정 관리');
    expect(find.text('전화번호 변경'), findsOneWidget);
    expect(find.text('로그인 기기'), findsOneWidget);
    expect(find.text('패스키/2단계 인증'), findsOneWidget);
    expect(find.text('계정 삭제'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '권한 관리');
    expect(find.text('마이크'), findsOneWidget);
    expect(find.text('알림'), findsOneWidget);
    expect(find.text('연락처'), findsOneWidget);
    expect(find.text('위치'), findsOneWidget);
    expect(find.text('사진/파일'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '개인정보 및 보안');
    expect(find.text('요청 메시지함 열기'), findsOneWidget);
    expect(find.text('광고 설정'), findsOneWidget);
    await tester.tap(find.text('요청 메시지함 열기'));
    await tester.pumpAndSettle();
    expect(find.text('아직 요청이 없습니다'), findsOneWidget);

    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '데이터 및 저장 공간');
    expect(find.text('내 데이터 다운로드'), findsOneWidget);
    await tester.tap(find.text('내 데이터 다운로드'));
    await tester.pumpAndSettle();
    expect(find.text('JSON 복사'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '안전센터');
    expect(find.text('신고한 내역'), findsOneWidget);
    expect(find.text('메시지/사용자 신고'), findsOneWidget);
    expect(find.text('스팸/사칭 신고'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '고객지원');
    expect(find.text('문의하기'), findsOneWidget);
    expect(find.text('음성 인식 오류 신고'), findsOneWidget);
    expect(find.text('앱 버전/기기 정보 자동 첨부'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '약관 및 정책');
    expect(find.text('이용약관'), findsOneWidget);
    expect(find.text('개인정보 처리방침'), findsOneWidget);
    expect(find.text('청소년 보호정책'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '앱 정보');
    expect(find.text('Verbal'), findsOneWidget);
    expect(find.text('1.0.0+1'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '언어');
    expect(find.text('한국어'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('日本語'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('메뉴'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '테마');
    expect(find.text('라이트 모드'), findsOneWidget);
    expect(find.text('다크 모드'), findsOneWidget);
  });

  testWidgets(
    'new chat flow uses normal chat for direct or group and separates open chat',
    (tester) async {
      await openHome(tester);

      await tester.tap(find.byTooltip('새 메시지'));
      await tester.pumpAndSettle();

      expect(find.text('채팅 시작'), findsOneWidget);
      expect(find.text('일반채팅'), findsOneWidget);
      expect(find.text('그룹채팅'), findsNothing);
      expect(find.text('오픈채팅'), findsOneWidget);
      expect(find.text('초대 링크로 참여'), findsOneWidget);

      await tester.tap(find.text('일반채팅'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('new-room-friend-search-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('friend-select-jihoon_lee')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('friend-select-jihoon_lee')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-room-create-button')));
      await tester.pumpAndSettle();
      expect(find.text('이지훈'), findsWidgets);
      expect(find.text('1:1 대화'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('새 메시지'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('일반채팅'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('friend-select-jihoon_lee')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('friend-select-yuna_jung')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('new-room-title-field')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('new-room-create-button')));
      await tester.pumpAndSettle();
      expect(find.text('그룹 대화'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('새 메시지'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('오픈채팅'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('open-room-title-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('open-room-friend-search-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('friend-select-jihoon_lee')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('open-room-handles-field')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('open-room-title-field')),
        '런칭 준비 오픈채팅',
      );
      await tester.tap(find.byKey(const ValueKey('friend-select-jihoon_lee')));
      await tester.pumpAndSettle();
      expect(find.text('이지훈 @jihoon_lee'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('open-room-create-button')));
      await tester.pumpAndSettle();
      expect(find.text('오픈채팅 링크가 생성되었습니다'), findsOneWidget);
      expect(find.textContaining('verbal.local/invite'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('open-room-copy-link-button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('open-room-enter-button')));
      await tester.pumpAndSettle();
      expect(find.text('런칭 준비 오픈채팅'), findsOneWidget);
      expect(find.text('오픈채팅'), findsOneWidget);
    },
  );

  testWidgets('demo mode supports in-app calendar create edit and delete', (
    tester,
  ) async {
    await openHome(tester);

    await tester.tap(find.byTooltip('일정'));
    await tester.pumpAndSettle();

    expect(find.text('일정'), findsWidgets);
    expect(find.text('Demo launch review'), findsWidgets);

    await tester.tap(find.byTooltip('알림 설정'));
    await tester.pumpAndSettle();
    expect(find.text('공휴일 국가'), findsOneWidget);
    expect(find.text('대한민국'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('직접 추가').last);
    await tester.pumpAndSettle();

    final today = DateTime.now();
    final todayText =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).controller?.text,
      todayText,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(3)).controller?.text,
      isEmpty,
    );

    var next = DateTime.now().add(const Duration(days: 1));
    while (HolidayCalendar.holidaysForDay(
      HolidayCountry.korea,
      next,
    ).isNotEmpty) {
      next = next.add(const Duration(days: 1));
    }
    final dateText =
        '${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
    await tester.enterText(find.byType(TextField).at(0), '제품 미팅');
    await tester.enterText(find.byType(TextField).at(1), '런칭 전 점검 항목 정리');
    await tester.enterText(find.byType(TextField).at(2), dateText);
    await tester.enterText(find.byType(TextField).at(3), '14:30');
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('저장'));
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('제품 미팅'), findsWidgets);

    await tester.tap(find.text('제품 미팅').first);
    await tester.pumpAndSettle();
    expect(find.text('런칭 전 점검 항목 정리'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '제품 미팅 수정');
    await tester.enterText(find.byType(TextField).at(1), '상세 내용도 함께 수정');
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();

    expect(find.text('제품 미팅 수정'), findsWidgets);

    await tester.tap(find.text('제품 미팅 수정').first);
    await tester.pumpAndSettle();
    expect(find.text('상세 내용도 함께 수정'), findsOneWidget);
    await tester.tap(find.byTooltip('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('제품 미팅 수정'), findsNothing);
  });

  testWidgets('demo mode supports message editing from the action sheet', (
    tester,
  ) async {
    await openChat(tester);

    await tester.longPress(find.text('네, 오후 8시 가능해요.'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '수정');

    await tester.enterText(
      find.byType(EditableText).last,
      'Yes, 8:30 PM works.',
    );
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();

    expect(find.text('Yes, 8:30 PM works.'), findsOneWidget);
    expect(find.text('수정됨(edited)'), findsOneWidget);
  });

  testWidgets('demo mode deletes own messages without a placeholder', (
    tester,
  ) async {
    await openChat(tester);

    await tester.longPress(find.text('네, 오후 8시 가능해요.'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '삭제');

    expect(find.text('대화 삭제'), findsNothing);
    expect(find.text('삭제된 메시지입니다.'), findsNothing);
    expect(find.text('네, 오후 8시 가능해요.'), findsNothing);
  });

  testWidgets('demo mode supports reactions, pinning, and chat search', (
    tester,
  ) async {
    await openChat(tester);

    await tester.longPress(find.text('네, 오후 8시 가능해요.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('👍'));
    await tester.pumpAndSettle();

    expect(find.text('👍 1'), findsOneWidget);

    await tester.longPress(find.text('네, 오후 8시 가능해요.'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '메시지 고정');

    expect(find.text('고정된 메시지'), findsOneWidget);

    await tester.longPress(find.text('고정된 메시지'));
    await tester.pumpAndSettle();
    expect(find.text('고정 해제'), findsOneWidget);

    await tester.tap(find.text('고정 해제'));
    await tester.pumpAndSettle();
    expect(find.text('고정된 메시지'), findsNothing);

    await tapMoreMenuItem(tester, '대화 검색');
    await tester.enterText(
      find.byKey(const ValueKey('chat-search-field')),
      '통화',
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘 저녁에 통화 가능해?'), findsOneWidget);
    expect(find.text('네, 오후 8시 가능해요.'), findsNothing);
  });

  testWidgets('demo mode supports chat calendar proposal voting and finalize', (
    tester,
  ) async {
    await openChat(tester);

    await tester.tap(find.byTooltip('첨부'));
    await tester.pumpAndSettle();
    await tapSheetTile(tester, '일정 제안');

    await tester.enterText(
      find.byKey(const ValueKey('calendar-proposal-title-field')),
      'Team dinner',
    );
    await tester.enterText(
      find.byKey(const ValueKey('calendar-proposal-details-field')),
      'Pick a time together',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('제안 보내기'));
    await tester.pumpAndSettle();
    await scrollChatToBottom(tester);

    expect(find.text('Team dinner'), findsOneWidget);
    expect(find.text('일정 투표 중'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('투표 저장'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1표'), findsWidgets);

    await tester.tap(find.text('확정').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('확정됨'), findsOneWidget);
    expect(find.text('내 일정에 추가'), findsOneWidget);
  });

  testWidgets(
    'demo mode supports attachments, schedule, translation, invite QR',
    (tester) async {
      await openChat(tester);

      await tester.longPress(find.text('오늘 저녁에 통화 가능해?'));
      await tester.pumpAndSettle();
      await tapSheetTile(tester, '영어로 번역');
      expect(find.text('오늘 저녁에 통화 가능해?'), findsWidgets);

      await tester.tap(find.byTooltip('첨부'));
      await tester.pumpAndSettle();
      await tapSheetTile(tester, '파일');
      await scrollChatToBottom(tester);
      expect(find.text('Verbal Brief.pdf'), findsOneWidget);

      await tester.tap(find.byTooltip('첨부'));
      await tester.pumpAndSettle();
      await tapSheetTile(tester, '위치');
      await scrollChatToBottom(tester);
      expect(find.textContaining('37.5665'), findsWidgets);

      await tester.enterText(
        find.byKey(const ValueKey('message-input-field')),
        'Send this later',
      );
      await tester.tap(find.byTooltip('예약 전송'));
      await tester.pumpAndSettle();
      expect(find.text('10 minutes'), findsNothing);
      expect(find.text('1 hour'), findsNothing);
      expect(find.text('Tomorrow 9 AM'), findsNothing);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final dateText =
          '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
      await tester.enterText(
        find.byKey(const ValueKey('schedule-date-field')),
        dateText,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('schedule-time-field')),
        '09:30',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('예약하기'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(find.text('Send this later'), findsOneWidget);
      await tester.longPress(find.text('Send this later'));
      await tester.pumpAndSettle();
      await tapSheetTile(tester, '지금 보내기');

      await tapMoreMenuItem(tester, '대화 정보');
      final inviteButton = find
          .ancestor(
            of: find.textContaining('QR').first,
            matching: find.byType(OutlinedButton),
          )
          .first;
      await tester.ensureVisible(inviteButton);
      await tester.tap(inviteButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('verbal.local/invite'), findsOneWidget);
    },
  );
}
