import {
  Component,
  input,
  output,
  model,
  viewChild,
  viewChildren,
  contentChild,
  contentChildren,
  signal,
  computed,
  effect,
  ElementRef,
  TemplateRef,
} from '@angular/core';

function trimString(value: string | undefined): string {
  return value?.trim() ?? '';
}

interface Item {
  id: number;
  name: string;
}

@Component({
  selector: 'app-signals',
  standalone: true,
  templateUrl: './signals.component.html',
})
export class SignalsComponent {
  simpleInput = input<string>();
  requiredInput = input.required<string>();
  aliasedInput = input<string>('', { alias: 'externalSignal' });
  transformedInput = input('', { transform: trimString });
  inputWithDefault = input('default value');
  numberInput = input<number>(0);

  clicked = output<MouseEvent>();
  customEvent = output<{ id: number; data: string }>();
  voidOutput = output<void>();

  count = model(0);
  selectedItem = model<Item | null>(null);
  toggleState = model(false);

  searchField = viewChild<ElementRef>('search');
  requiredChild = viewChild.required<ElementRef>('requiredElement');
  templateChild = viewChild<TemplateRef<unknown>>('signalTemplate');

  allItems = viewChildren<ElementRef>('signalItem');
  allButtons = viewChildren<ElementRef>('signalButton');

  projectedContent = contentChild<ElementRef>('projectedSignal');
  projectedRequired = contentChild.required<ElementRef>('requiredProjected');

  allProjected = contentChildren<ElementRef>('projectedSignalItem');

  firstName = signal('John');
  lastName = signal('Doe');
  age = signal(30);
  items = signal<Item[]>([
    { id: 1, name: 'Item 1' },
    { id: 2, name: 'Item 2' },
  ]);

  fullName = computed(() => `${this.firstName()} ${this.lastName()}`);
  isAdult = computed(() => this.age() >= 18);
  itemCount = computed(() => this.items().length);
  doubleCount = computed(() => this.count() * 2);

  greeting = computed(() => {
    const name = this.fullName();
    const adult = this.isAdult();
    return adult ? `Hello, ${name}` : `Hi, ${name}`;
  });

  constructor() {
    effect(() => {
      console.log('Full name changed:', this.fullName());
    });

    effect(() => {
      console.log('Count is now:', this.count());
      console.log('Double count:', this.doubleCount());
    });

    effect(() => {
      const item = this.selectedItem();
      if (item) {
        console.log('Selected:', item.name);
      }
    });
  }

  updateFirstName(name: string): void {
    this.firstName.set(name);
  }

  updateLastName(name: string): void {
    this.lastName.set(name);
  }

  incrementAge(): void {
    this.age.update((current) => current + 1);
  }

  addItem(name: string): void {
    this.items.update((current) => [...current, { id: current.length + 1, name }]);
  }

  removeItem(id: number): void {
    this.items.update((current) => current.filter((item) => item.id !== id));
  }

  incrementCount(): void {
    this.count.update((c) => c + 1);
  }

  decrementCount(): void {
    this.count.update((c) => c - 1);
  }

  selectItem(item: Item): void {
    this.selectedItem.set(item);
  }

  toggle(): void {
    this.toggleState.update((state) => !state);
  }

  emitClick(event: MouseEvent): void {
    this.clicked.emit(event);
  }

  emitCustom(): void {
    this.customEvent.emit({ id: 1, data: 'custom data' });
  }

  emitVoid(): void {
    this.voidOutput.emit();
  }

  accessViewChild(): void {
    const search = this.searchField();
    if (search) {
      search.nativeElement.focus();
    }
    const required = this.requiredChild();
    console.log(required.nativeElement);
  }

  accessViewChildren(): void {
    const items = this.allItems();
    items.forEach((item) => console.log(item.nativeElement));
  }
}
