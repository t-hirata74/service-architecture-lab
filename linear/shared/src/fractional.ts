/**
 * Fractional indexing — kanban 列内の並び順キー (issues.sort_order)。
 *
 * 既存 2 キーの「辞書順で厳密に間」に入る新キーを生成することで、
 * 並び替え時に他の行を UPDATE せず 1 行の書き換えで済ませる (Linear / Figma が使う手法)。
 *
 * 不変条件:
 * - キーは ORDER_DIGITS のみで構成され、空でなく、末尾が最小桁 '0' にならない
 *   (末尾 '0' を許すと、そのキーの直前に入るキーが生成できなくなる)
 * - keyBetween(a, b) は常に a < result < b (null は無限遠)
 */

export const ORDER_DIGITS =
  '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

const MIN_DIGIT = ORDER_DIGITS[0] as string;

export function isValidOrderKey(key: string): boolean {
  if (key.length === 0) return false;
  if (key.endsWith(MIN_DIGIT)) return false;
  for (const ch of key) {
    if (!ORDER_DIGITS.includes(ch)) return false;
  }
  return true;
}

function assertValidOrderKey(key: string): void {
  if (!isValidOrderKey(key)) {
    throw new Error(`invalid order key: "${key}"`);
  }
}

/**
 * a と b の間に入るキーを返す。null は「端」(a=null なら先頭挿入、b=null なら末尾追加)。
 */
export function keyBetween(a: string | null, b: string | null): string {
  if (a !== null) assertValidOrderKey(a);
  if (b !== null) assertValidOrderKey(b);
  if (a !== null && b !== null && a >= b) {
    throw new Error(`keyBetween: "${a}" >= "${b}"`);
  }
  return mid(a ?? '', b);
}

/**
 * a (空文字 = 下限なし) と b (null = 上限なし) の間のキー。
 * a 側は不足桁を MIN_DIGIT 埋めとして比較する。
 */
function mid(a: string, b: string | null): string {
  if (b !== null) {
    // 共通 prefix を剥がして残りを再帰 (a は不足分を '0' とみなす)
    let n = 0;
    while (n < b.length && (a[n] ?? MIN_DIGIT) === b[n]) n++;
    if (n > 0) {
      return b.slice(0, n) + mid(a.slice(n), b.slice(n));
    }
  }

  const da = a.length > 0 ? ORDER_DIGITS.indexOf(a[0] as string) : 0;
  const db =
    b === null
      ? ORDER_DIGITS.length
      : ORDER_DIGITS.indexOf(b[0] as string);

  if (db - da > 1) {
    // 間に桁が空いている → 中央の 1 桁
    return ORDER_DIGITS[Math.round((da + db) / 2)] as string;
  }

  // da と db が連続している
  if (b !== null && b.length > 1) {
    // b の先頭 1 桁は a より大きく、かつ b より小さい ('1' < '1x')
    return b.slice(0, 1);
  }
  // a の先頭桁を引き継ぎ、残りと「上限なし」の間を伸ばす
  return (ORDER_DIGITS[da] as string) + mid(a.slice(1), null);
}
