import { Component } from '@angular/core';
import { TransformChildComponent } from './transform-child.component';

@Component({
  selector: 'app-transform-inline-parent',
  standalone: true,
  imports: [TransformChildComponent],
  template: `<app-transform-child [disabled]="true" />`,
})
export class TransformInlineParentComponent {}
