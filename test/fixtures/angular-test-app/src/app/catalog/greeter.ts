export interface Greeter {
  greet(): string;
}

export class CatalogGreeter implements Greeter {
  greet(): string {
    return 'hi';
  }
}

export function useGreeter(greeter: Greeter): string {
  return greeter.greet();
}
