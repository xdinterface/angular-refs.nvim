import { Directive, input } from '@angular/core';

@Directive({ selector: '[appCatHighlight]', standalone: true })
export class CatalogHighlightDirective {
  appCatHighlight = input('');
}
