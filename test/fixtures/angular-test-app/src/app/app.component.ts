import { Component } from '@angular/core';
import { TsPatternsComponent } from './components/ts-patterns/ts-patterns.component';
import { DecoratorsComponent } from './components/decorators/decorators.component';
import { SignalsComponent } from './components/signals/signals.component';
import { TemplatePatternsComponent } from './components/template-patterns/template-patterns.component';
import { ParentComponent } from './components/parent-child/parent.component';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [
    TsPatternsComponent,
    DecoratorsComponent,
    SignalsComponent,
    TemplatePatternsComponent,
    ParentComponent,
  ],
  template: `
    <h1>Angular Test App</h1>
    <app-ts-patterns></app-ts-patterns>
    <app-decorators
      [simpleInput]="decoratorInput"
      [externalName]="aliasedValue"
      [requiredInput]="requiredValue"
      [boolInput]="true"
      [external]="complexValue"
      (simpleOutput)="onSimpleOutput()"
      (externalEvent)="onAliasedOutput($event)"
    ></app-decorators>
    <app-signals
      [simpleInput]="signalInput"
      [requiredInput]="signalRequired"
      [externalSignal]="signalAliased"
      (clicked)="onSignalClick($event)"
      [(count)]="signalCount"
    ></app-signals>
    <app-template-patterns></app-template-patterns>
    <app-parent></app-parent>
  `,
})
export class AppComponent {
  decoratorInput = 'decorator input value';
  aliasedValue = 'aliased value';
  requiredValue = 'required value';
  complexValue = 42;

  signalInput = 'signal input';
  signalRequired = 'signal required';
  signalAliased = 'signal aliased';
  signalCount = 0;

  onSimpleOutput(): void {}
  onAliasedOutput(value: string): void {}
  onSignalClick(event: MouseEvent): void {}
}
