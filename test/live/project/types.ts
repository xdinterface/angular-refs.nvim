import { Pipe } from '@angular/core';
import { ControlValueAccessor as CVA } from '@angular/forms';
export const callback = () => {};
export function top() { callback(); callback(); }
export class Types {
  first = 1; second = 2;
  private secret() {}
  protected guarded() {}
  static create() {}
  arrow = () => this.secret();
  *iterate() { yield this.first; }
  async generic<T>(value: T) { this.guarded(); return value; }
  overloaded(value: string): string;
  overloaded(value: number): number;
  overloaded(value: string | number) { return value; }
  get value() { return this.second; }
  set value(next: number) { this.second = next; }
  ngOnInit() {} // Not an Angular lifecycle hook: this is an ordinary class.
  run() { this.overloaded('x'); this.value = this.value; this.arrow(); }
}
Types.create();
@Pipe({ name: 'identity', standalone: true })
export class IdentityPipe { transform(value: unknown) { return value; } }
export class Accessor implements CVA {
  writeValue(value: unknown) {}
  registerOnChange(fn: unknown) {}
  registerOnTouched(fn: unknown) {}
  setDisabledState(disabled: boolean) {}
}
export class Parameters {
  constructor(public parameterProp = '') {}
  static same() {}
  same() {}
  run() { this.same(); Parameters.same(); return this.parameterProp; }
}
