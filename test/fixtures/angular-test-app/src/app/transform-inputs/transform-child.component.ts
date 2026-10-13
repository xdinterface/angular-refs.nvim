import { Component, Input, booleanAttribute, numberAttribute } from '@angular/core';

@Component({
  selector: 'app-transform-child',
  standalone: true,
  template: `
    <p>{{ disabled }} {{ sizeValue }} {{ neverBound }}</p>
  `,
})
export class TransformChildComponent {
  @Input({ transform: booleanAttribute }) disabled = false;
  @Input({ alias: 'size', transform: numberAttribute }) sizeValue = 0;
  @Input({ transform: booleanAttribute }) neverBound = false;
  @Input({ transform: booleanAttribute }) unusedFlag = false;
}
