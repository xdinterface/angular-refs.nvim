import { Component, OnInit } from '@angular/core';
interface Action { save(): void; }
@Component({ selector: 'owner-a', standalone: true, template: '<button (click)="service.save()">A</button>' })
export class A implements OnInit, Action {
  service = new B();
  ngOnInit() {}
  save() {}
}
@Component({ selector: 'owner-b', standalone: true, template: '<button (click)="save()">B</button>' })
export class B implements OnInit, Action {
  ngOnInit() {}
  save() {}
}
new B().save();
const action: Action = new B();
action.save();
