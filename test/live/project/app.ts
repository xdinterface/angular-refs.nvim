import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { of } from 'rxjs';
import { Child } from './child';

@Component({ selector: 'app-root', standalone: true, imports: [CommonModule, FormsModule, Child], templateUrl: './app.html' })
export class App implements OnInit {
  asyncData$ = of('hello');
  twoWayValue = '';
  visible = true;
  title = 'title';
  ngOnInit() {}
  save() {}
  getItems() { return [1, 2]; }
  run() { this.save(); }
}
