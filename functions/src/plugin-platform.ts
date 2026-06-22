export type PluginPlatform =
  | "generic"
  | "telegram"
  | "slack"
  | "teams"
  | "kakao"
  | "line"
  | "meta";

export interface PluginMessageCardInput {
  platform: PluginPlatform;
  transcript: string;
  audioUrl?: string;
  audioId?: string;
  senderName?: string;
  calendarTitle?: string;
  calendarStartAt?: string;
}

export interface PluginMessageCard {
  platform: PluginPlatform;
  plainText: string;
  richCard: Record<string, unknown>;
}

export class PluginMessageCardInputError extends Error {}

export function pluginPlatform(value: unknown): PluginPlatform {
  const normalized =
    typeof value === "string" ? value.trim().toLowerCase() : "";
  if (
    normalized === "telegram" ||
    normalized === "slack" ||
    normalized === "teams" ||
    normalized === "kakao" ||
    normalized === "line" ||
    normalized === "meta"
  ) {
    return normalized;
  }
  return "generic";
}

export function pluginContentType(value: unknown): string {
  const contentType =
    typeof value === "string" ? value.trim().toLowerCase() : "";
  if (
    contentType === "audio/webm" ||
    contentType === "audio/wav" ||
    contentType === "audio/mpeg" ||
    contentType === "audio/mp4" ||
    contentType === "audio/m4a" ||
    contentType === "audio/x-m4a"
  ) {
    return contentType;
  }
  return "audio/mp4";
}

export function pluginAudioExtension(contentType: string): string {
  switch (pluginContentType(contentType)) {
    case "audio/webm":
      return ".webm";
    case "audio/wav":
      return ".wav";
    case "audio/mpeg":
      return ".mp3";
    default:
      return ".m4a";
  }
}

export function pluginMessageCardInput(
  value: Record<string, unknown>,
): PluginMessageCardInput {
  const transcript = stringValue(value.transcript).slice(0, 4000);
  return {
    platform: pluginPlatform(value.platform),
    transcript,
    audioUrl: optionalStringValue(value.audioUrl).slice(0, 2048) || undefined,
    audioId: optionalStringValue(value.audioId).slice(0, 128) || undefined,
    senderName:
      optionalStringValue(value.senderName).slice(0, 80) || undefined,
    calendarTitle:
      optionalStringValue(value.calendarTitle).slice(0, 120) || undefined,
    calendarStartAt:
      optionalStringValue(value.calendarStartAt).slice(0, 64) || undefined,
  };
}

export function renderPluginMessageCard(
  input: PluginMessageCardInput,
): PluginMessageCard {
  const transcript = input.transcript.trim() || "Voice message";
  const title = input.senderName
    ? `${input.senderName} via Verbal`
    : "Verbal voice message";
  const audioLabel = input.audioUrl ? `\nAudio: ${input.audioUrl}` : "";
  const calendarLabel =
    input.calendarTitle && input.calendarStartAt
      ? `\nCalendar: ${input.calendarTitle} (${input.calendarStartAt})`
      : "";
  const plainText = `${transcript}${audioLabel}${calendarLabel}`;

  if (input.platform === "slack") {
    return {
      platform: input.platform,
      plainText,
      richCard: {
        text: plainText,
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: `*${escapeSlack(title)}*\n${escapeSlack(transcript)}`,
            },
          },
          ...(input.audioUrl
            ? [
                {
                  type: "actions",
                  elements: [
                    {
                      type: "button",
                      text: { type: "plain_text", text: "Play audio" },
                      url: input.audioUrl,
                    },
                  ],
                },
              ]
            : []),
        ],
      },
    };
  }

  if (input.platform === "teams") {
    return {
      platform: input.platform,
      plainText,
      richCard: {
        type: "AdaptiveCard",
        version: "1.4",
        body: [
          { type: "TextBlock", text: title, weight: "Bolder" },
          { type: "TextBlock", text: transcript, wrap: true },
          ...(input.audioUrl
            ? [{ type: "TextBlock", text: input.audioUrl, wrap: true }]
            : []),
        ],
      },
    };
  }

  if (input.platform === "kakao") {
    return {
      platform: input.platform,
      plainText,
      richCard: {
        object_type: "text",
        text: plainText.slice(0, 200),
        link: input.audioUrl
          ? {
              web_url: input.audioUrl,
              mobile_web_url: input.audioUrl,
            }
          : undefined,
        button_title: input.audioUrl ? "Open voice" : undefined,
      },
    };
  }

  if (input.platform === "telegram") {
    return {
      platform: input.platform,
      plainText,
      richCard: {
        text: plainText,
        parse_mode: "HTML",
        reply_markup: input.audioUrl
          ? {
              inline_keyboard: [
                [{ text: "Play audio", url: input.audioUrl }],
              ],
            }
          : undefined,
      },
    };
  }

  return {
    platform: input.platform,
    plainText,
    richCard: {
      title,
      text: transcript,
      audioUrl: input.audioUrl || null,
      audioId: input.audioId || null,
      calendar:
        input.calendarTitle && input.calendarStartAt
          ? {
              title: input.calendarTitle,
              startAt: input.calendarStartAt,
            }
          : null,
    },
  };
}

function stringValue(value: unknown): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new PluginMessageCardInputError("transcript is required.");
  }
  return value.trim();
}

function optionalStringValue(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function escapeSlack(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}
