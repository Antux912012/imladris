# TypeScript Reference

Write strictly typed TypeScript modules and Imladris community extensions with discriminated unions, `readonly` contracts, and zero `any` types.

## Discriminated Unions & Generic Helpers

```typescript
export type SdvState =
  | { readonly status: "verified"; readonly sha256: string }
  | { readonly status: "mismatch"; readonly expected: string; readonly actual: string };

export interface CodedSpan {
  readonly id: string;
  readonly codeId: string;
  readonly entityId?: string;
  readonly sdv: SdvState;
}

export function filterVerified(spans: readonly CodedSpan[]): CodedSpan[] {
  return spans.filter((s) => s.sdv.status === "verified");
}
```
