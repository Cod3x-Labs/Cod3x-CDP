export function isNullOrWhitespace(input: string | null | undefined): boolean {
  return input === null || input === undefined || input.trim() === "";
}
