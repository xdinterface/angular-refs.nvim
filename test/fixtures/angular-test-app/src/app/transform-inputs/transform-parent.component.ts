import { Component } from '@angular/core';
import { TransformChildComponent } from './transform-child.component';
import { TransformFlagDirective } from './transform-flag.directive';

@Component({
  selector: 'app-transform-parent',
  standalone: true,
  imports: [TransformChildComponent, TransformFlagDirective],
  templateUrl: './transform-parent.component.html',
})
export class TransformParentComponent {
  flag = true;
  count = 2;
  items = [1, 2];
  noop(): void {}
}
