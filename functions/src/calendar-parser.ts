export interface CalendarParseOptions {
  now?: Date;
  timezone?: string;
  defaultDurationMinutes?: number;
}

export interface ParsedCalendarCommand {
  title: string | null;
  startAt: Date | null;
  endAt: Date | null;
  timezone: string;
  missingFields: string[];
}

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;
const DEFAULT_TIMEZONE = "Asia/Seoul";
const DEFAULT_DURATION_MINUTES = 60;

const koreanNumberMap = new Map<string, number>([
  ["영", 0],
  ["공", 0],
  ["한", 1],
  ["하나", 1],
  ["일", 1],
  ["두", 2],
  ["둘", 2],
  ["이", 2],
  ["세", 3],
  ["셋", 3],
  ["삼", 3],
  ["네", 4],
  ["넷", 4],
  ["사", 4],
  ["다섯", 5],
  ["오", 5],
  ["여섯", 6],
  ["육", 6],
  ["일곱", 7],
  ["칠", 7],
  ["여덟", 8],
  ["팔", 8],
  ["아홉", 9],
  ["구", 9],
  ["열", 10],
  ["십", 10],
  ["스물", 20],
  ["스무", 20],
  ["서른", 30],
]);

export function parseCalendarCommand(
  transcript: string,
  options: CalendarParseOptions = {},
): ParsedCalendarCommand {
  const timezone = options.timezone || DEFAULT_TIMEZONE;
  const defaultDurationMinutes =
    options.defaultDurationMinutes || DEFAULT_DURATION_MINUTES;
  const text = normalizeTranscript(transcript);
  const now = options.now || new Date();
  const currentKstYear = new Date(now.getTime() + KST_OFFSET_MS).getUTCFullYear();

  const year = parseYear(text, currentKstYear);
  const month = readUnitNumber(text, "월");
  const day = readUnitNumber(text, "일");
  const time = parseTime(text);
  const title = parseTitle(text);

  const missingFields: string[] = [];
  if (year == null) {
    missingFields.push("year");
  }
  if (month == null || day == null) {
    missingFields.push("date");
  }
  if (!time) {
    missingFields.push("time");
  }
  if (!title) {
    missingFields.push("title");
  }

  let startAt: Date | null = null;
  let endAt: Date | null = null;
  if (year != null && month != null && day != null && time) {
    startAt = kstLocalDateToUtc(year, month, day, time.hour, time.minute);
    if (Number.isNaN(startAt.getTime())) {
      startAt = null;
      endAt = null;
      if (!missingFields.includes("date")) {
        missingFields.push("date");
      }
    } else {
      endAt = new Date(
        startAt.getTime() + defaultDurationMinutes * 60 * 1000,
      );
    }
  }

  return {
    title,
    startAt,
    endAt,
    timezone,
    missingFields,
  };
}

function normalizeTranscript(value: string) {
  return value.replace(/\s+/g, " ").trim();
}

function parseYear(text: string, currentYear: number) {
  if (/올\s*해|올해|금\s*년|금년/.test(text)) {
    return currentYear;
  }
  if (/내\s*년|내년/.test(text)) {
    return currentYear + 1;
  }
  const explicit = text.match(/([0-9]{4})\s*년/);
  return explicit ? Number(explicit[1]) : null;
}

function readUnitNumber(text: string, unit: "월" | "일") {
  const escapedUnit = unit.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = text.match(new RegExp(`([0-9]{1,2}|[가-힣]+)\\s*${escapedUnit}`));
  if (!match) {
    return null;
  }
  return parseKoreanNumber(match[1]);
}

function parseTime(text: string) {
  const match = text.match(
    /(오전|오후|아침|저녁|밤|낮)?\s*([0-9]{1,2}|[가-힣]+)\s*시(?:\s*([0-9]{1,2}|[가-힣]+)\s*분)?(?:에)?/,
  );
  if (!match) {
    return null;
  }
  const period = match[1] || "";
  const rawHour = parseKoreanNumber(match[2]);
  if (rawHour == null) {
    return null;
  }
  const rawMinute = match[3] == null ? 0 : parseKoreanNumber(match[3]);
  if (rawMinute == null) {
    return null;
  }

  let hour = rawHour;
  if ((period === "오후" || period === "저녁" || period === "밤") && hour < 12) {
    hour += 12;
  }
  if ((period === "오전" || period === "아침") && hour === 12) {
    hour = 0;
  }
  if (hour < 0 || hour > 23 || rawMinute < 0 || rawMinute > 59) {
    return null;
  }
  return { hour, minute: rawMinute };
}

function parseKoreanNumber(value: string) {
  const normalized = value.replace(/\s+/g, "");
  if (/^[0-9]+$/.test(normalized)) {
    return Number(normalized);
  }
  if (koreanNumberMap.has(normalized)) {
    return koreanNumberMap.get(normalized) ?? null;
  }
  if (normalized.includes("십")) {
    const parts = normalized.split("십");
    const tens = parts[0] ? koreanNumberMap.get(parts[0]) ?? null : 1;
    const ones = parts[1] ? koreanNumberMap.get(parts[1]) ?? null : 0;
    if (tens != null && ones != null) {
      return tens * 10 + ones;
    }
  }
  for (const [prefix, valueBase] of [
    ["스물", 20],
    ["스무", 20],
    ["서른", 30],
  ] as const) {
    if (normalized.startsWith(prefix)) {
      const suffix = normalized.slice(prefix.length);
      const ones = suffix ? koreanNumberMap.get(suffix) ?? null : 0;
      return ones == null ? null : valueBase + ones;
    }
  }
  return null;
}

function parseTitle(text: string) {
  const timeMatch = text.match(
    /(오전|오후|아침|저녁|밤|낮)?\s*([0-9]{1,2}|[가-힣]+)\s*시(?:\s*([0-9]{1,2}|[가-힣]+)\s*분)?(?:에|에다가|으로)?\s*(.+)$/u,
  );
  let candidate = timeMatch?.[4] || "";
  candidate = candidate
    .replace(/^(제목은|제목|이름은|이름)\s*/u, "")
    .replace(/\s*(이라는|라는|로|으로)?\s*(일정|약속|스케줄)\s*(을|를)?\s*(추가|등록|저장|만들어|만들|잡아|생성).*$/u, "")
    .replace(/\s*(일정|약속|스케줄)\s*$/u, "")
    .trim();
  if (!candidate || candidate.length > 120) {
    return null;
  }
  return candidate;
}

function kstLocalDateToUtc(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
) {
  const date = new Date(Date.UTC(year, month - 1, day, hour - 9, minute, 0, 0));
  const kst = new Date(date.getTime() + KST_OFFSET_MS);
  if (
    kst.getUTCFullYear() !== year ||
    kst.getUTCMonth() !== month - 1 ||
    kst.getUTCDate() !== day ||
    kst.getUTCHours() !== hour ||
    kst.getUTCMinutes() !== minute
  ) {
    return new Date(Number.NaN);
  }
  return date;
}
