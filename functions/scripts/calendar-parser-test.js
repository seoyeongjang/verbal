const assert = require("node:assert/strict");
const { parseCalendarCommand } = require("../lib/calendar-parser.js");

const now = new Date("2026-05-28T03:00:00.000Z");

{
  const parsed = parseCalendarCommand(
    "올해 7월 3일 오후 2시에 A라는 일정 추가해줘",
    { now },
  );
  assert.equal(parsed.title, "A");
  assert.equal(parsed.startAt.toISOString(), "2026-07-03T05:00:00.000Z");
  assert.equal(parsed.endAt.toISOString(), "2026-07-03T06:00:00.000Z");
  assert.deepEqual(parsed.missingFields, []);
}

{
  const parsed = parseCalendarCommand(
    "내년 12월 25일 오전 9시 30분에 병원 예약이라는 일정 등록해줘",
    { now },
  );
  assert.equal(parsed.title, "병원 예약");
  assert.equal(parsed.startAt.toISOString(), "2027-12-25T00:30:00.000Z");
}

{
  const parsed = parseCalendarCommand("7월 3일 오후 2시에 일정 추가", {
    now,
  });
  assert.equal(parsed.title, null);
  assert.equal(parsed.startAt, null);
  assert.deepEqual(parsed.missingFields.sort(), ["title", "year"].sort());
}

console.log("calendar-parser-ok");
