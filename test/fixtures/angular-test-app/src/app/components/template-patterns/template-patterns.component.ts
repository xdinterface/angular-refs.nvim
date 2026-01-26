import { Component, ViewChild, TemplateRef, ElementRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Observable, of, BehaviorSubject } from 'rxjs';

interface Item {
  id: number;
  name: string;
  category: string;
}

interface NestedObj {
  deep: {
    property: string;
    value: number;
  };
}

@Component({
  selector: 'app-template-patterns',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './template-patterns.component.html',
})
export class TemplatePatternsComponent {
  simpleProperty = 'simple value';
  anotherProperty = 'another value';
  condition = true;
  trueValue = 'is true';
  falseValue = 'is false';
  arrayProp = ['first', 'second', 'third'];

  nested: NestedObj = {
    deep: {
      property: 'deep property',
      value: 42,
    },
  };

  elementId = 'my-element';
  isActive = true;
  textColor = 'blue';
  dataId = 'data-123';
  inputValue = 'input content';
  childConfig = { key: 'value' };

  twoWayValue = 'two-way';
  parentValue = 'parent';

  showContent = true;
  alternateCondition = false;
  ifContent = 'if block content';
  elseIfContent = 'else if content';
  elseContent = 'else content';

  items: Item[] = [
    { id: 1, name: 'Item 1', category: 'A' },
    { id: 2, name: 'Item 2', category: 'B' },
    { id: 3, name: 'Item 3', category: 'A' },
  ];
  emptyMessage = 'No items available';

  status: 'active' | 'pending' | 'inactive' = 'active';
  activeLabel = 'Status: Active';
  pendingLabel = 'Status: Pending';
  defaultLabel = 'Status: Unknown';

  deferredData = { large: 'data' };
  loadingText = 'Loading...';
  placeholderText = 'Placeholder content';

  firstName = 'John';
  lastName = 'Doe';

  dateValue = new Date();
  textValue = 'lowercase text';
  price = 99.99;
  pipeArg1 = 'arg1';
  pipeArg2 = 'arg2';

  asyncData$: Observable<string> = of('async value');
  asyncSubject$ = new BehaviorSubject<number>(0);

  legacyCondition = true;
  legacyItems = ['legacy1', 'legacy2', 'legacy3'];
  legacyStatus: 'on' | 'off' = 'on';

  templateContext = { name: 'context name', value: 100 };

  @ViewChild('myInput') myInputRef!: ElementRef<HTMLInputElement>;
  @ViewChild('myTemplate') myTemplateRef!: TemplateRef<unknown>;

  methodCall(): string {
    return 'method result';
  }

  handleClick(): void {
    console.log('clicked');
  }

  handleClickWithEvent(event: MouseEvent): void {
    console.log('clicked with event', event);
  }

  onInput(event: Event): void {
    console.log('input', event);
  }

  onEnter(): void {
    console.log('enter pressed');
  }

  onCustom(event: unknown): void {
    console.log('custom event', event);
  }

  trackById(index: number, item: Item): number {
    return item.id;
  }

  trackByIndex(index: number): number {
    return index;
  }

  getItems(): Item[] {
    return this.items;
  }

  toggleShow(): void {
    this.showContent = !this.showContent;
  }

  changeStatus(newStatus: 'active' | 'pending' | 'inactive'): void {
    this.status = newStatus;
  }

  addItem(): void {
    this.items = [...this.items, { id: this.items.length + 1, name: `Item ${this.items.length + 1}`, category: 'C' }];
  }

  focusInput(): void {
    this.myInputRef?.nativeElement.focus();
  }
}
