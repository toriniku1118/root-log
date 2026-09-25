import sharp from 'sharp';

/**
 * 写真を縮小し、位置情報(EXIF・XMP など)をすべて削除した JPEG にする。
 * sharp は withMetadata / keepExif を指定しない限りメタデータを書き出さない。この性質に頼っているため、
 * 依存ライブラリを更新したら src/image.test.ts で位置情報が消えることを必ず確認する。
 */
export function cleanImage(original: Buffer, longEdge: number, maxInputPixels: number) {
  return sharp(original, { limitInputPixels: maxInputPixels })
    .rotate() // 向きの情報を画像に反映してから、向きの情報も削除
    .resize({ width: longEdge, height: longEdge, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 82, mozjpeg: true })    .toBuffer({ resolveWithObject: true });
}
