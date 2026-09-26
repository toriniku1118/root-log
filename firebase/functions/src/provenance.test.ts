// 来歴の判定(provenance.ts)の自動テスト:どの条件で「来歴つき」になり、なにが来歴にならないかを固定する。
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import {
  PROVENANCE_CLOCK_SKEW_MS,
  PROVENANCE_MAX_DELAY_MS,
  extractCaptureTime,
  isWithinCaptureWindow,
  judgeProvenance,
  type CaptureTime,
} from './provenance.js';

const MIN = 60_000;
const HOUR = 3_600_000;
const RECEIVED = Date.UTC(2026, 8, 26, 3, 0, 0); // 受信時刻(UTC)

async function jpegWithExif(exif: Record<string, Record<string, string>>): Promise<Buffer | undefined> {
  const data = await sharp({ create: { width: 20, height: 20, channels: 3, background: '#3a7' } })
    .withExif(exif)
    .jpeg()
    .toBuffer();
  return (await sharp(data).metadata()).exif;
}

describe('撮影時刻の窓(isWithinCaptureWindow)', () => {
  it('上限は10分。ちょうど10分は入り、10分1秒は入らない(時差が分かるとき)', () => {
    assert.equal(PROVENANCE_MAX_DELAY_MS, 10 * MIN);
    assert.equal(isWithinCaptureWindow(RECEIVED, RECEIVED - 10 * MIN, true), true);
    assert.equal(isWithinCaptureWindow(RECEIVED, RECEIVED - 10 * MIN - 1000, true), false);
  });

  it('撮影の直後(0秒)は入る', () => {
    assert.equal(isWithinCaptureWindow(RECEIVED, RECEIVED, true), true);
  });

  it('端末の時計が進んでいても、1分までは許す。1分1秒は入らない', () => {
    assert.equal(PROVENANCE_CLOCK_SKEW_MS, MIN);
    assert.equal(isWithinCaptureWindow(RECEIVED, RECEIVED + MIN, true), true);
    assert.equal(isWithinCaptureWindow(RECEIVED, RECEIVED + MIN + 1000, true), false);
  });

  it('時差が分かるときは、1時間単位のずれを許さない', () => {
    assert.equal(isWithinCaptureWindow(RECEIVED, RECEIVED - HOUR, true), false);
    assert.equal(isWithinCaptureWindow(RECEIVED, RECEIVED + HOUR, true), false);
  });

  it('時差が分からないときは、1時間単位のずれ(±14時間)を許す。15時間のずれは許さない', () => {
    // 撮影時刻を UTC として読んだ値が、実際の時刻より数時間ずれる(端末の現地時刻のため)場合
    for (const h of [-14, -9, -1, 0, 1, 9, 14]) {
      assert.equal(isWithinCaptureWindow(RECEIVED, RECEIVED - 5 * MIN + h * HOUR, false), true, `${h}時間のずれ`);
    }
    assert.equal(isWithinCaptureWindow(RECEIVED, RECEIVED - 5 * MIN + 15 * HOUR, false), false);
    assert.equal(isWithinCaptureWindow(RECEIVED, RECEIVED - 5 * MIN - 15 * HOUR, false), false);
  });

  it('時差が分からなくても、1時間単位を外れた時刻(30分のずれなど)は許さない', () => {
    assert.equal(isWithinCaptureWindow(RECEIVED, RECEIVED - 30 * MIN, false), false);
    assert.equal(isWithinCaptureWindow(RECEIVED, RECEIVED - 30 * MIN + 3 * HOUR, false), false);
  });
});

describe('来歴の判定(judgeProvenance)', () => {
  const nowCapture: CaptureTime = { capturedAt: new Date(RECEIVED - 2 * MIN), offsetKnown: true };
  const judge = (over: Partial<Parameters<typeof judgeProvenance>[0]>) =>
    judgeProvenance({ source: 'camera', captured: nowCapture, receivedMs: RECEIVED, isDuplicate: false, ...over });

  it('アプリ内カメラ・撮影時刻が窓の中・重複なし → ok(来歴つき)', () => {
    assert.deepEqual(judge({}), { provenance: true, provenanceReason: 'ok' });
  });

  it('端末の写真(gallery)は、撮影時刻が窓の中でも来歴にならない', () => {
    assert.deepEqual(judge({ source: 'gallery' }), { provenance: false, provenanceReason: 'gallery' });
  });

  it('端末の写真は、撮影時刻がなくても理由は gallery', () => {
    assert.deepEqual(judge({ source: 'gallery', captured: null }), { provenance: false, provenanceReason: 'gallery' });
  });

  it('カメラでも撮影時刻がなければ no_capture_time', () => {
    assert.deepEqual(judge({ captured: null }), { provenance: false, provenanceReason: 'no_capture_time' });
  });

  it('撮影時刻が古すぎれば capture_time_mismatch', () => {
    const old: CaptureTime = { capturedAt: new Date(RECEIVED - 11 * MIN), offsetKnown: true };
    assert.deepEqual(judge({ captured: old }), { provenance: false, provenanceReason: 'capture_time_mismatch' });
  });

  it('撮影時刻が未来すぎても capture_time_mismatch(受信より2分先)', () => {
    const future: CaptureTime = { capturedAt: new Date(RECEIVED + 2 * MIN), offsetKnown: true };
    assert.deepEqual(judge({ captured: future }), { provenance: false, provenanceReason: 'capture_time_mismatch' });
  });

  it('重複は、撮影時刻が窓の中でも来歴にならない(写真の使い回し対策)', () => {
    assert.deepEqual(judge({ isDuplicate: true }), { provenance: false, provenanceReason: 'duplicate' });
  });

  it('重複は、ほかの理由より優先する(gallery・撮影時刻なしでも duplicate)', () => {
    assert.equal(judge({ isDuplicate: true, source: 'gallery' }).provenanceReason, 'duplicate');
    assert.equal(judge({ isDuplicate: true, captured: null }).provenanceReason, 'duplicate');
  });

  it('来歴つきになるのは、理由が ok のときだけ(全部の組み合わせで確かめる)', () => {
    const times: Array<CaptureTime | null> = [
      null,
      nowCapture,
      { capturedAt: new Date(RECEIVED - HOUR), offsetKnown: true },
      { capturedAt: new Date(RECEIVED - HOUR), offsetKnown: false },
    ];
    for (const source of ['camera', 'gallery'] as const) {
      for (const captured of times) {
        for (const isDuplicate of [false, true]) {
          const r = judge({ source, captured, isDuplicate });
          assert.equal(r.provenance, r.provenanceReason === 'ok', JSON.stringify({ source, captured, isDuplicate, r }));
        }
      }
    }
  });
});

describe('EXIF からの撮影時刻の取り出し(extractCaptureTime)', () => {
  it('EXIF がなければ null', () => {
    assert.equal(extractCaptureTime(undefined), null);
  });

  it('撮影時刻(DateTimeOriginal)を読む。時差がなければ、UTC として読み、offsetKnown は false', async () => {
    const exif = await jpegWithExif({ IFD2: { DateTimeOriginal: '2026:09:26 10:00:00' } });
    const c = extractCaptureTime(exif);
    assert.ok(c);
    assert.equal(c.capturedAt.toISOString(), '2026-09-26T10:00:00.000Z');
    assert.equal(c.offsetKnown, false);
  });

  it('編集時刻(DateTime)だけで、撮影時刻がなければ null(編集時刻は使わない)', async () => {
    const exif = await jpegWithExif({ IFD0: { DateTime: '2026:09:26 10:00:00' } });
    assert.equal(extractCaptureTime(exif), null);
  });

  it('撮影時刻と編集時刻があるときは、撮影時刻を使う', async () => {
    const exif = await jpegWithExif({
      IFD0: { DateTime: '2026:09:26 12:00:00' },
      IFD2: { DateTimeOriginal: '2026:09:26 10:00:00' },
    });
    assert.equal(extractCaptureTime(exif)?.capturedAt.toISOString(), '2026-09-26T10:00:00.000Z');
  });

  it('時差(OffsetTimeOriginal)があれば UTC に直し、offsetKnown は true', async () => {
    const exif = await jpegWithExif({ IFD2: { DateTimeOriginal: '2026:09:26 12:00:00', OffsetTimeOriginal: '+09:00' } });
    const c = extractCaptureTime(exif);
    assert.ok(c);
    assert.equal(c.capturedAt.toISOString(), '2026-09-26T03:00:00.000Z'); // 日本の12:00 = 03:00 UTC
    assert.equal(c.offsetKnown, true);
  });

  it('マイナスの時差・30分単位の時差も直せる', async () => {
    const west = extractCaptureTime(await jpegWithExif({ IFD2: { DateTimeOriginal: '2026:09:26 12:00:00', OffsetTimeOriginal: '-05:00' } }));
    assert.equal(west?.capturedAt.toISOString(), '2026-09-26T17:00:00.000Z');
    const india = extractCaptureTime(await jpegWithExif({ IFD2: { DateTimeOriginal: '2026:09:26 12:00:00', OffsetTimeOriginal: '+05:30' } }));
    assert.equal(india?.capturedAt.toISOString(), '2026-09-26T06:30:00.000Z');
  });

  it('時差の書式が違えば、時差なしとして扱う(offsetKnown は false)', async () => {
    const c = extractCaptureTime(await jpegWithExif({ IFD2: { DateTimeOriginal: '2026:09:26 12:00:00', OffsetTimeOriginal: 'JST' } }));
    assert.equal(c?.offsetKnown, false);
    assert.equal(c?.capturedAt.toISOString(), '2026-09-26T12:00:00.000Z');
  });

  it('壊れた EXIF は、例外にせず null', () => {
    assert.equal(extractCaptureTime(Buffer.from('これはEXIFではありません')), null);
    assert.equal(extractCaptureTime(Buffer.alloc(0)), null);
  });

  it('取り出した値で判定できる:撮影の直後は ok、1時間前(時差あり)は capture_time_mismatch', async () => {
    const at = (h: number, m: number) => Date.UTC(2026, 8, 26, h, m, 0);
    const exif = await jpegWithExif({ IFD2: { DateTimeOriginal: '2026:09:26 12:00:00', OffsetTimeOriginal: '+09:00' } });
    const captured = extractCaptureTime(exif);
    assert.equal(judgeProvenance({ source: 'camera', captured, receivedMs: at(3, 2), isDuplicate: false }).provenanceReason, 'ok');
    assert.equal(
      judgeProvenance({ source: 'camera', captured, receivedMs: at(4, 2), isDuplicate: false }).provenanceReason,
      'capture_time_mismatch',
    );
  });
});
