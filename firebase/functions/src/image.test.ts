// 写真の処理(cleanImage)の自動テスト:位置情報などが必ず消えることを確認する
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import exifReader from 'exif-reader';
import { cleanImage } from './image.js';

const MAX_PIXELS = 40_000_000;

const exif = {
  IFD0: { Make: 'TestCam', Model: 'Secret-Phone-9000', Orientation: '6' },
  IFD2: { DateTimeOriginal: '2026:09:25 10:00:00' },
  IFD3: {
    GPSLatitudeRef: 'N',
    GPSLatitude: '35/1 40/1 0/1',
    GPSLongitudeRef: 'E',
    GPSLongitude: '139/1 45/1 0/1',
  },
};

async function base(width: number, height: number) {
  return sharp({ create: { width, height, channels: 3, background: '#3a7' } });
}

async function jpegWithGps(width = 120, height = 80) {
  return (await base(width, height)).withExif(exif).jpeg().toBuffer();
}
async function pngWithGps() {
  return (await base(120, 80)).withExif(exif).png().toBuffer();
}

function containsText(buf: Buffer, text: string) {
  return buf.includes(Buffer.from(text, 'latin1'));
}

describe('cleanImage(位置情報の削除)', () => {
  it('テスト用の画像に、位置情報が本当に入っている(空振りのテストにしないための確認)', async () => {
    const meta = await sharp(await jpegWithGps()).metadata();
    assert.ok(meta.exif, 'EXIF がある');
    const parsed = exifReader(meta.exif!) as { GPSInfo?: Record<string, unknown> };
    assert.ok(parsed.GPSInfo?.GPSLatitude, 'GPS の緯度がある');
    assert.ok(parsed.GPSInfo?.GPSLongitude, 'GPS の経度がある');
  });

  for (const [name, make] of [
    ['JPEG', jpegWithGps],
    ['PNG', pngWithGps],
  ] as const) {
    it(`${name}:縮小後の画像に EXIF・GPS・機種名が残らない`, async () => {
      const { data } = await cleanImage(await make(), 1600, MAX_PIXELS);
      const meta = await sharp(data).metadata();
      assert.equal(meta.format, 'jpeg');
      assert.equal(meta.exif, undefined);
      assert.equal(meta.xmp, undefined);
      assert.equal(meta.iptc, undefined);
      assert.equal(meta.tifftagPhotoshop, undefined);
      assert.equal(containsText(data, 'Exif'), false);
      assert.equal(containsText(data, 'GPS'), false);
      assert.equal(containsText(data, 'Secret-Phone-9000'), false);
      assert.equal(containsText(data, 'ns.adobe.com'), false);
    });
  }

  it('向きの情報(Orientation)は画像に反映され、向きのタグは残らない', async () => {
    // withExif は Orientation を 1 に上書きするため、向きは withMetadata で付ける
    const rotated = await (await base(120, 80)).jpeg().withMetadata({ orientation: 6 }).toBuffer();
    assert.equal((await sharp(rotated).metadata()).orientation, 6);
    const { info, data } = await cleanImage(rotated, 1600, MAX_PIXELS);
    assert.equal(info.width, 80); // Orientation=6(90度回転)なので縦横が入れ替わる
    assert.equal(info.height, 120);
    assert.equal((await sharp(data).metadata()).orientation, undefined);
  });

  it('長辺が指定より大きい画像は縮小し、小さい画像は拡大しない', async () => {
    const big = await (await base(3200, 2400)).jpeg().toBuffer();
    const small = await (await base(300, 200)).jpeg().toBuffer();
    const a = await cleanImage(big, 1600, MAX_PIXELS);
    assert.equal(Math.max(a.info.width, a.info.height), 1600);
    const b = await cleanImage(small, 1600, MAX_PIXELS);
    assert.equal(b.info.width, 300);
    assert.equal(b.info.height, 200);
  });

  it('画素数の上限を超える画像は処理しない', async () => {
    const img = await (await base(400, 400)).jpeg().toBuffer();
    await assert.rejects(cleanImage(img, 1600, 100_000));
  });
});
