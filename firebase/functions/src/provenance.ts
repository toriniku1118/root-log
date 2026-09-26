// 来歴の判定(Firebase に依存しない関数)。`processUpload`(index.ts)が使う。自動テストは provenance.test.ts。
//
// 注意:撮影元と EXIF は端末側の情報で、改造したアプリなら偽装できる。確実に保証できるのは「サーバーが受信した時刻」だけ。
// 画面では「この日時までに撮影された写真」と表示する(外部設計 3.7.1)。
import exifReader from 'exif-reader';

/** 来歴として認める条件:アプリ内カメラで撮影し、撮影時刻と受信時刻の差がこの範囲内 */
export const PROVENANCE_MAX_DELAY_MS = 10 * 60 * 1000;
/** 端末の時計が少し進んでいても許す(受信が撮影より前になる分) */
export const PROVENANCE_CLOCK_SKEW_MS = 60_000;

export type ProvenanceReason = 'ok' | 'gallery' | 'no_capture_time' | 'capture_time_mismatch' | 'duplicate';
export type PhotoSource = 'camera' | 'gallery';

export interface CaptureTime {
  /** 撮影時刻(UTC の時刻として扱える形)。 */
  capturedAt: Date;
  /** 時差(OffsetTimeOriginal)が分かり、UTC に直せたか。 */
  offsetKnown: boolean;
}

/**
 * EXIF の撮影時刻(DateTimeOriginal)を取り出す。編集時刻(Image.DateTime)は使わない。
 * exif-reader は撮影時刻を UTC として読む(実際は端末の現地時刻)。OffsetTimeOriginal(例 `+09:00`)があれば
 * UTC に直して `offsetKnown` を true にする。読めなければ null(EXIF が壊れていても例外にしない)。
 */
export function extractCaptureTime(exif: Buffer | undefined): CaptureTime | null {
  if (!exif) return null;
  try {
    const photo = exifReader(exif)?.Photo as Record<string, unknown> | undefined;
    const dt = photo?.DateTimeOriginal;
    if (!(dt instanceof Date) || Number.isNaN(dt.getTime())) return null;
    const off = photo?.OffsetTimeOriginal;
    const m = typeof off === 'string' ? /^([+-])(\d{2}):(\d{2})$/.exec(off) : null;
    if (m) {
      const sign = m[1] === '+' ? 1 : -1;
      return { capturedAt: new Date(dt.getTime() - sign * (Number(m[2]) * 60 + Number(m[3])) * 60_000), offsetKnown: true };
    }
    return { capturedAt: dt, offsetKnown: false };
  } catch {
    return null;
  }
}

/**
 * 撮影時刻と受信時刻の差が、来歴として認める範囲(-1分〜10分)かを判定する。
 * 時差が分からないとき(`offsetKnown` が false)だけ、1時間単位のずれ(-14〜+14時間)を許す。
 */
export function isWithinCaptureWindow(receivedMs: number, capturedMs: number, offsetKnown: boolean): boolean {
  const HOUR = 3_600_000;
  const range = offsetKnown ? 0 : 14;
  for (let k = -range; k <= range; k++) {
    const delay = receivedMs - (capturedMs - k * HOUR); // 受信は撮影より後
    if (delay >= -PROVENANCE_CLOCK_SKEW_MS && delay <= PROVENANCE_MAX_DELAY_MS) return true;
  }
  return false;
}

export interface ProvenanceInput {
  source: PhotoSource;
  captured: CaptureTime | null;
  receivedMs: number;
  /** 同じ画像がすでに登録されているか(重複検出)。 */
  isDuplicate: boolean;
}

/**
 * 来歴の判定。来歴つき(`provenance`)になるのは、理由が `ok` のときだけ。
 * 重複は、ほかの理由より優先する(写真の使い回しを来歴にしない)。
 */
export function judgeProvenance(input: ProvenanceInput): { provenance: boolean; provenanceReason: ProvenanceReason } {
  if (input.isDuplicate) return { provenance: false, provenanceReason: 'duplicate' };
  if (input.source !== 'camera') return { provenance: false, provenanceReason: 'gallery' };
  if (!input.captured) return { provenance: false, provenanceReason: 'no_capture_time' };
  if (!isWithinCaptureWindow(input.receivedMs, input.captured.capturedAt.getTime(), input.captured.offsetKnown)) {
    return { provenance: false, provenanceReason: 'capture_time_mismatch' };
  }
  return { provenance: true, provenanceReason: 'ok' };
}
