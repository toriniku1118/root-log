import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    // エミュレーターのデータを共有するため、テストファイルは順番に実行する
    fileParallelism: false,
    testTimeout: 20_000,
  },
});
