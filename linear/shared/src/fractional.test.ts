import { describe, expect, it } from 'vitest';
import { isValidOrderKey, keyBetween, ORDER_DIGITS } from './fractional';

describe('keyBetween', () => {
  it('最初のキー (両端 null) を返す', () => {
    const k = keyBetween(null, null);
    expect(isValidOrderKey(k)).toBe(true);
  });

  it('末尾追加: a < result', () => {
    let prev = keyBetween(null, null);
    for (let i = 0; i < 200; i++) {
      const next = keyBetween(prev, null);
      expect(next > prev).toBe(true);
      expect(isValidOrderKey(next)).toBe(true);
      prev = next;
    }
  });

  it('先頭挿入: result < b (繰り返しても末尾 "0" にならない)', () => {
    let first = keyBetween(null, null);
    for (let i = 0; i < 200; i++) {
      const next = keyBetween(null, first);
      expect(next < first).toBe(true);
      expect(isValidOrderKey(next)).toBe(true);
      first = next;
    }
  });

  it('同じ 2 点間への連続挿入 (二分割の深掘り)', () => {
    let a = keyBetween(null, null);
    let b = keyBetween(a, null);
    for (let i = 0; i < 200; i++) {
      const m = keyBetween(a, b);
      expect(a < m && m < b).toBe(true);
      expect(isValidOrderKey(m)).toBe(true);
      // 交互に左右の区間を狭めて偏ったケースも踏む
      if (i % 2 === 0) a = m;
      else b = m;
    }
  });

  it('fuzz: ランダム位置への 1000 回挿入で常に全順序を保つ', () => {
    // 再現性のため固定シードの線形合同法
    let seed = 42;
    const rand = (n: number) => {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      return seed % n;
    };

    const keys: string[] = [keyBetween(null, null)];
    for (let i = 0; i < 1000; i++) {
      const pos = rand(keys.length + 1); // 0..length (両端含む)
      const a = pos === 0 ? null : (keys[pos - 1] as string);
      const b = pos === keys.length ? null : (keys[pos] as string);
      const k = keyBetween(a, b);
      expect(isValidOrderKey(k)).toBe(true);
      if (a !== null) expect(k > a).toBe(true);
      if (b !== null) expect(k < b).toBe(true);
      keys.splice(pos, 0, k);
    }
    const sorted = [...keys].sort();
    expect(keys).toEqual(sorted);
    expect(new Set(keys).size).toBe(keys.length);
  });

  it('a >= b は例外', () => {
    expect(() => keyBetween('V', 'V')).toThrow();
    expect(() => keyBetween('W', 'V')).toThrow();
  });

  it('不正キーは例外 (末尾 0 / 空 / 不正文字)', () => {
    expect(() => keyBetween('V0', null)).toThrow();
    expect(() => keyBetween('', null)).toThrow();
    expect(() => keyBetween('V!', null)).toThrow();
  });

  it('ORDER_DIGITS は ASCII 昇順 (辞書順比較の前提)', () => {
    const chars = ORDER_DIGITS.split('');
    expect(chars).toEqual([...chars].sort());
  });
});
