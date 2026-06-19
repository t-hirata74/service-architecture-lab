/** ドメイン層が投げる HTTP ステータス付きエラー。app.ts の onError が拾う。 */
export class DomainError extends Error {
  constructor(
    public readonly status: 400 | 404 | 409 | 422,
    message: string,
  ) {
    super(message);
    this.name = 'DomainError';
  }
}
