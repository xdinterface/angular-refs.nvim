import { Component } from '@angular/core';
import { DataService } from '../../services/data.service';

export const EXPORTED_CONST = 'exported constant value';
const LOCAL_CONST = 'local constant';
let mutableVar = 0;
var legacyVar = 'legacy';

const sourceObj = { destructured: 'value', nested: { deep: 'nested' } };
const { destructured, nested: { deep } } = sourceObj;

const sourceArr = [1, 2, 3, 4, 5];
const [first, second, ...rest] = sourceArr;

export function exportedFunction(): string {
  return 'exported';
}

function localFunction(): void {
  console.log(LOCAL_CONST);
}

async function asyncFunction(): Promise<void> {
  await Promise.resolve();
}

function* generatorFunction(): Generator<number> {
  yield 1;
  yield 2;
}

export const arrowFn = (): string => 'arrow';
const localArrow = (x: number): number => x * 2;
const asyncArrow = async (): Promise<string> => 'async arrow';

export interface ExportedInterface {
  id: number;
  name: string;
}

interface LocalInterface {
  key: string;
  value: unknown;
}

export type ExportedType = string | number | boolean;
type LocalType = { key: string; count: number };

export enum ExportedEnum {
  First = 'FIRST',
  Second = 'SECOND',
  Third = 'THIRD',
}

enum LocalEnum {
  X = 1,
  Y = 2,
  Z = 3,
}

@Component({
  selector: 'app-ts-patterns',
  standalone: true,
  templateUrl: './ts-patterns.component.html',
})
export class TsPatternsComponent {
  publicProp = 'public property';
  readonly readonlyProp = 'readonly property';
  private privateProp = 'private property';
  protected protectedProp = 'protected property';
  static staticProp = 'static property';

  optionalProp?: string;
  definiteProp!: string;

  arrayProp: string[] = ['one', 'two', 'three'];
  objectProp: LocalType = { key: 'test', count: 42 };
  enumProp = ExportedEnum.First;

  publicMethod(): string {
    this.privateMethod();
    return this.publicProp;
  }

  private privateMethod(): void {
    console.log(this.privateProp);
  }

  protected protectedMethod(): string {
    return this.protectedProp;
  }

  static staticMethod(): string {
    return TsPatternsComponent.staticProp;
  }

  async asyncMethod(): Promise<string> {
    return Promise.resolve('async result');
  }

  methodWithParams(name: string, count: number): string {
    return `${name}: ${count}`;
  }

  get computedValue(): string {
    return `computed: ${this.publicProp}`;
  }

  set computedValue(value: string) {
    this.publicProp = value;
  }

  get readonlyComputed(): number {
    return this.arrayProp.length;
  }

  constructor(private dataService: DataService) {
    localFunction();
    mutableVar++;
  }

  useExternals(): void {
    console.log(EXPORTED_CONST, destructured, deep, first);
    console.log(exportedFunction(), arrowFn());
    console.log(ExportedEnum.Second, LocalEnum.X);
    const gen = generatorFunction();
    gen.next();
  }
}
