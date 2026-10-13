import { Pipe, PipeTransform } from '@angular/core';

@Pipe({ name: 'catalogPipe', standalone: true })
export class CatalogPipe implements PipeTransform {
  transform(value: string): string {
    return value;
  }
}
