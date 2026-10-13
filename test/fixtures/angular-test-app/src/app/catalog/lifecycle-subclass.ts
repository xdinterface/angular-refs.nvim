import { Component } from '@angular/core';
import { LifeA } from './lifecycle';

@Component({ selector: 'app-life-d', standalone: true, template: '' })
export class LifeD extends LifeA {
  override ngOnInit(): void {
    super.ngOnInit();
  }
}
