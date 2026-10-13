import { Component, OnInit } from '@angular/core';

@Component({ selector: 'app-life-a', standalone: true, template: '' })
export class LifeA implements OnInit {
  ngOnInit(): void {}
}

@Component({ selector: 'app-life-b', standalone: true, template: '' })
export class LifeB extends LifeA {
  override ngOnInit(): void {
    super.ngOnInit();
  }
}

@Component({ selector: 'app-life-c', standalone: true, template: '' })
export class LifeC implements OnInit {
  ngOnInit(): void {}
}

export function bootLifeA(): void {
  new LifeA().ngOnInit();
}

export function bootLifeC(c: LifeC): void {
  c.ngOnInit();
}

export function bootAnyOnInit(x: OnInit): void {
  x.ngOnInit();
}
