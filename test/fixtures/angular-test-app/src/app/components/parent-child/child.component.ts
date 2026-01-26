import {
  Component,
  Input,
  Output,
  EventEmitter,
  input,
  output,
  model,
  booleanAttribute,
  numberAttribute,
} from '@angular/core';

interface ChildConfig {
  label: string;
  value: number;
}

@Component({
  selector: 'app-child',
  standalone: true,
  template: `
    <div class="child-component">
      <h4>Child Component</h4>

      <!-- Decorator-based inputs -->
      <p>Simple Input: {{ simpleInput }}</p>
      <p>Aliased Input: {{ realInputName }}</p>
      <p>Required Input: {{ requiredInput }}</p>
      <p>Bool Input: {{ boolInput }}</p>
      <p>Number Input: {{ numInput }}</p>
      <p>Config: {{ configInput?.label }} - {{ configInput?.value }}</p>

      <!-- Signal-based inputs -->
      <p>Signal Input: {{ signalInput() }}</p>
      <p>Required Signal: {{ requiredSignalInput() }}</p>
      <p>Aliased Signal: {{ aliasedSignalInput() }}</p>

      <!-- Model -->
      <p>Count Model: {{ count() }}</p>
      <p>Value Model: {{ value() }}</p>

      <!-- Outputs -->
      <button (click)="emitSimple()">Emit Simple</button>
      <button (click)="emitAliased()">Emit Aliased</button>
      <button (click)="emitSignal()">Emit Signal</button>
      <button (click)="incrementCount()">Increment Count</button>
      <button (click)="updateValue()">Update Value</button>
    </div>
  `,
})
export class ChildComponent {
  @Input() simpleInput: string = '';
  @Input('aliasedName') realInputName: string = '';
  @Input({ required: true }) requiredInput!: string;
  @Input({ transform: booleanAttribute }) boolInput = false;
  @Input({ transform: numberAttribute }) numInput = 0;
  @Input() configInput?: ChildConfig;
  @Input() optionalInput?: string;

  @Output() simpleOutput = new EventEmitter<void>();
  @Output('aliasedEvent') realOutputName = new EventEmitter<string>();
  @Output() dataOutput = new EventEmitter<{ id: number }>();

  signalInput = input<string>('');
  requiredSignalInput = input.required<string>();
  aliasedSignalInput = input<string>('', { alias: 'externalSignalInput' });
  transformedSignalInput = input('', { transform: (v: string) => v.toUpperCase() });

  signalOutput = output<MouseEvent>();
  aliasedSignalOutput = output<string>({ alias: 'externalSignalOutput' });

  count = model(0);
  value = model<string>('');

  emitSimple(): void {
    this.simpleOutput.emit();
  }

  emitAliased(): void {
    this.realOutputName.emit('aliased event from child');
  }

  emitData(): void {
    this.dataOutput.emit({ id: 1 });
  }

  emitSignal(): void {
    this.aliasedSignalOutput.emit('signal output from child');
  }

  incrementCount(): void {
    this.count.update((c) => c + 1);
  }

  updateValue(): void {
    this.value.set('updated from child');
  }

  childMethod(): string {
    return 'child method result';
  }

  private privateChildMethod(): void {
    console.log('private');
  }
}
