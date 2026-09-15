import { Component as NgComponent, Input, input, model, HostListener } from '@angular/core';

@NgComponent({ selector: 'test-child', standalone: true,
  template: '<button (click)="emitSimple()">{{ realName }} {{ signalName() }} {{ value() }}</button>',
  host: { '(click)': 'hostClick()' }
})
export class Child {
  @Input('publicName') realName = '';
  signalName = input<string>('', { alias: 'signalAlias' });
  value = model('');
  emitSimple() {}
  hostClick() {}
  @HostListener('window:resize') resize() {}
  ngOnDestroy() {}
}
