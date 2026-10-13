import { Component, EventEmitter, Input, Output, booleanAttribute, input, model, numberAttribute, output } from '@angular/core';

@Component({
  selector: 'app-catalog-child',
  standalone: true,
  inputs: ['inputsArrayProp'],
  template: `
    <p>{{ childIn }}</p>
    <p>{{ tBool }} {{ tAlias }} {{ tSignal() }}</p>
    <p>{{ aliasedIn }}</p>
    <p>{{ signalIn() }}</p>
    <p>{{ requiredIn() }}</p>
    <p>{{ childModel() }}</p>
    <button (click)="fire()"></button>
  `,
})
export class CatalogChildComponent {
  @Input() childIn = '';
  @Input({ transform: booleanAttribute }) tBool = false;
  @Input({ alias: 'tAliasExt', transform: numberAttribute }) tAlias = 0;
  tSignal = input(false, { transform: booleanAttribute });
  @Input('aliasName') aliasedIn = '';
  signalIn = input<string>();
  requiredIn = input.required<number>();
  inputsArrayProp = '';
  childModel = model(0);
  childOut = output<string>();
  @Output() legacyOut = new EventEmitter<void>();

  fire(): void {
    this.childOut.emit('x');
    this.legacyOut.emit();
  }

  publicChildMethod(): string {
    return 'x';
  }
}
