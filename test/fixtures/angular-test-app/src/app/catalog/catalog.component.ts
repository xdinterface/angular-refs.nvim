import { Component, HostBinding, HostListener, computed, signal } from '@angular/core';
import {
  AsyncPipe,
  DecimalPipe,
  NgClass,
  NgFor,
  NgIf,
  NgSwitch,
  NgSwitchCase,
  NgTemplateOutlet,
  UpperCasePipe,
} from '@angular/common';
import { FormsModule } from '@angular/forms';
import { trigger } from '@angular/animations';
import { Observable, of } from 'rxjs';
import { CatalogChildComponent } from './catalog-child.component';
import { CatalogHighlightDirective } from './catalog-highlight.directive';
import { CatalogPipe } from './catalog.pipe';

export enum CatEnum {
  A = 'a',
}

@Component({
  selector: 'app-catalog',
  standalone: true,
  imports: [
    AsyncPipe, DecimalPipe, NgClass, NgFor, NgIf, NgSwitch, NgSwitchCase, NgTemplateOutlet,
    UpperCasePipe, FormsModule, CatalogChildComponent, CatalogHighlightDirective, CatalogPipe,
  ],
  templateUrl: './catalog.component.html',
  animations: [trigger('fade', [])],
  host: {
    '(click)': 'hostMetaHandler()',
    '[class.big]': 'hostMetaProp',
  },
})
export class CatalogComponent {
  // --- interpolation forms ---
  interp = 'a';
  interpMethod(): string { return 'a'; }
  chainObj = { a: { b: 1 } };
  safeNav: { name: string } | null = null;
  nonNull: { name: string } | null = { name: 'x' };
  ternaryCond = true;
  ternaryA = 'a';
  ternaryB = 'b';
  nullishProp: string | null = null;
  formatFn(v: number): string { return String(v); }
  methodArg = 1;
  thisPrefixed = 'a';
  anyCast = { x: 1 };
  optionalFn?: () => string;
  tplLiteral = 'a';
  getterBacking = 1;
  get getterProp(): number { return this.getterBacking; }
  set setterProp(v: number) { this.getterBacking = v; }
  enumHolder = CatEnum;

  // --- property / attribute / class / style bindings ---
  propBind = 'a';
  bindPrefix = 'a';
  attrBind = 'a';
  classBind = true;
  styleBind = 10;
  ngClassObj = true;
  arrayLiteralItem = 1;

  // --- event bindings ---
  eventHandler(): void {}
  eventWithArg(_e: Event): void {}
  onPrefixHandler(): void {}
  keyedEvent(): void {}
  assignTarget = false;
  multiStmtA(): void {}
  multiStmtB(): void {}
  onModelChange(_v: string): void {}

  // --- two-way ---
  twoWayModel = 'a';

  // --- control flow (@ blocks) ---
  ifCond = true;
  ifAs: string | null = 'a';
  elseIfCond = false;
  forItems = [1, 2];
  forItems2 = [1, 2];
  trackFn(_i: number, item: number): number { return item; }
  forInner = 'a';
  emptyMsg = 'empty';
  switchVal = 'a';
  caseVal = 'a';
  deferWhen = true;
  deferBody = 'a';
  deferPlaceholder = 'a';
  letSource = 'a';

  // --- legacy structural directives ---
  ngIfCond = true;
  ngTemplateIf = true;
  ngForItems = [1];
  ngForTrack(_i: number, item: number): number { return item; }
  ngSwitchVal = 'a';
  ngSwitchCaseVal = 'a';
  templateOutletCtx = { $implicit: 1 };

  // --- pipes ---
  pipeInput = 'a';
  pipeArg = '1.0-0';
  asyncObs$: Observable<string> = of('a');

  // --- signals ---
  signalVal = signal(1);
  computedVal = computed(() => this.signalVal() * 2);

  // --- animations (@ prefix in templates) ---
  animState = 'open';
  animDone(): void {}

  // --- i18n ICU ---
  icuCount = 1;

  // --- passed down to child component / directive ---
  childInputValue = 'a';
  onChildOut(_v: string): void {}
  modelSync = 0;
  directiveColor = 'red';

  // --- host metadata + host decorators (framework-invoked) ---
  hostMetaProp = true;
  hostMetaHandler(): void {}
  @HostBinding('class.hb') hostBindingProp = true;
  @HostListener('window:resize') onResize(): void {}

  // --- TypeScript-only usage ---
  callsTsOnly(): void { this.tsOnlyMethod(); }
  tsOnlyMethod(): void {}

  // --- used only from a spec file ---
  testOnlyMethod(): void {}

  // --- control: never used anywhere ---
  unusedMember = 'never';
}
