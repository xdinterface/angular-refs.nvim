import { Component, ViewChild } from '@angular/core';
import { ChildComponent } from './child.component';

@Component({
  selector: 'app-parent',
  standalone: true,
  imports: [ChildComponent],
  templateUrl: './parent.component.html',
})
export class ParentComponent {
  parentSimple = 'parent simple value';
  parentAliased = 'parent aliased value';
  parentRequired = 'parent required value';
  parentBool = true;
  parentNumber = 42;
  parentConfig = { label: 'Parent Config', value: 100 };
  parentOptional = 'optional value';

  parentSignalInput = 'parent signal input';
  parentSignalRequired = 'parent signal required';
  parentSignalAliased = 'parent signal aliased';

  parentCount = 0;
  parentValue = 'parent value';

  outputReceived = '';
  aliasedOutputReceived = '';
  dataOutputReceived: { id: number } | null = null;
  signalOutputReceived = '';

  @ViewChild(ChildComponent) childRef!: ChildComponent;

  onSimpleOutput(): void {
    this.outputReceived = 'simple output received';
  }

  onAliasedOutput(value: string): void {
    this.aliasedOutputReceived = value;
  }

  onDataOutput(data: { id: number }): void {
    this.dataOutputReceived = data;
  }

  onSignalOutput(event: MouseEvent): void {
    console.log('signal output received', event);
  }

  onAliasedSignalOutput(value: string): void {
    this.signalOutputReceived = value;
  }

  callChildMethod(): void {
    if (this.childRef) {
      const result = this.childRef.childMethod();
      console.log(result);
    }
  }

  updateParentCount(): void {
    this.parentCount++;
  }

  updateParentValue(): void {
    this.parentValue = 'updated parent value';
  }

  resetAll(): void {
    this.parentCount = 0;
    this.parentValue = 'parent value';
    this.outputReceived = '';
    this.aliasedOutputReceived = '';
    this.dataOutputReceived = null;
    this.signalOutputReceived = '';
  }
}
