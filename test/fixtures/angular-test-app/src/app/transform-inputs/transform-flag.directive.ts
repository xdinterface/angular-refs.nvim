import { Directive, Input, booleanAttribute } from '@angular/core';

@Directive({ selector: '[appFlag]', standalone: true })
export class TransformFlagDirective {
  @Input({ transform: booleanAttribute }) appFlag = false;
}
