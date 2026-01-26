import {
  Component,
  Input,
  Output,
  EventEmitter,
  ViewChild,
  ViewChildren,
  ContentChild,
  ContentChildren,
  ElementRef,
  TemplateRef,
  QueryList,
  booleanAttribute,
  numberAttribute,
} from '@angular/core';
import { ChildComponent } from '../parent-child/child.component';

@Component({
  selector: 'app-decorators',
  standalone: true,
  templateUrl: './decorators.component.html',
  host: {
    '[class.active]': 'isActive',
    '[class.disabled]': 'isDisabled',
    '[attr.data-id]': 'componentId',
    '[attr.aria-label]': 'ariaLabel',
    '[style.opacity]': 'opacity',
    '(click)': 'onHostClick($event)',
    '(mouseenter)': 'onMouseEnter()',
    '(mouseleave)': 'onMouseLeave()',
    '(window:resize)': 'onResize($event)',
    '(document:keydown.escape)': 'onEscape()',
  },
})
export class DecoratorsComponent {
  @Input() simpleInput: string = '';
  @Input('externalName') aliasedInput: string = '';
  @Input({ required: true }) requiredInput!: string;
  @Input({ transform: booleanAttribute }) boolInput = false;
  @Input({ alias: 'external', transform: numberAttribute }) complexInput = 0;
  @Input() optionalInput?: string;

  @Output() simpleOutput = new EventEmitter<void>();
  @Output('externalEvent') aliasedOutput = new EventEmitter<string>();
  @Output() dataOutput = new EventEmitter<{ id: number; name: string }>();

  @ViewChild('inputRef') inputElement!: ElementRef<HTMLInputElement>;
  @ViewChild('buttonRef') buttonElement!: ElementRef<HTMLButtonElement>;
  @ViewChild(ChildComponent) childComponent!: ChildComponent;
  @ViewChild('staticRef', { static: true }) staticRef!: ElementRef;
  @ViewChild('templateRef') templateRef!: TemplateRef<unknown>;
  @ViewChild('readRef', { read: ElementRef }) readElement!: ElementRef;

  @ViewChildren('listItem') listItems!: QueryList<ElementRef>;
  @ViewChildren(ChildComponent) childComponents!: QueryList<ChildComponent>;
  @ViewChildren('multiRef') multiRefs!: QueryList<ElementRef>;

  @ContentChild('projected') projectedContent!: ElementRef;
  @ContentChild(TemplateRef) projectedTemplate!: TemplateRef<unknown>;
  @ContentChild('headerSlot', { static: true }) headerSlot!: ElementRef;

  @ContentChildren('projectedItem') projectedItems!: QueryList<ElementRef>;
  @ContentChildren(ChildComponent, { descendants: true }) nestedChildren!: QueryList<ChildComponent>;

  isActive = false;
  isDisabled = false;
  componentId = 'decorators-component';
  ariaLabel = 'Decorators test component';
  opacity = '1';

  regularProperty = 'regular value';
  anotherProperty = 42;

  onHostClick(event: MouseEvent): void {
    console.log('Host clicked', event);
    this.isActive = !this.isActive;
  }

  onMouseEnter(): void {
    this.opacity = '0.8';
  }

  onMouseLeave(): void {
    this.opacity = '1';
  }

  onResize(event: Event): void {
    console.log('Window resized', event);
  }

  onEscape(): void {
    this.isActive = false;
  }

  emitSimple(): void {
    this.simpleOutput.emit();
  }

  emitAliased(): void {
    this.aliasedOutput.emit('aliased event data');
  }

  emitData(): void {
    this.dataOutput.emit({ id: 1, name: 'test' });
  }

  regularMethod(): string {
    return this.regularProperty;
  }

  methodWithViewChild(): void {
    if (this.inputElement) {
      this.inputElement.nativeElement.focus();
    }
    if (this.childComponent) {
      console.log(this.childComponent);
    }
  }

  methodWithViewChildren(): void {
    this.listItems.forEach((item) => console.log(item));
    this.childComponents.forEach((child) => console.log(child));
  }
}
