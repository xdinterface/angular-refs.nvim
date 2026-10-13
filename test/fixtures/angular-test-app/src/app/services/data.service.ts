import { Injectable, signal, computed } from '@angular/core';
import { Observable, of, BehaviorSubject, Subject } from 'rxjs';
import { map, delay } from 'rxjs/operators';

export interface Item {
  id: number;
  name: string;
  description: string;
  category: string;
  price: number;
  active: boolean;
}

export interface User {
  id: number;
  username: string;
  email: string;
  role: 'admin' | 'user' | 'guest';
}

@Injectable({ providedIn: 'root' })
export class DataService {
  readonly items = signal<Item[]>([
    { id: 1, name: 'Item 1', description: 'First item', category: 'A', price: 10, active: true },
    { id: 2, name: 'Item 2', description: 'Second item', category: 'B', price: 20, active: true },
    { id: 3, name: 'Item 3', description: 'Third item', category: 'A', price: 30, active: false },
  ]);

  readonly currentUser = signal<User | null>(null);
  readonly isLoading = signal(false);
  readonly error = signal<string | null>(null);

  readonly itemCount = computed(() => this.items().length);
  readonly activeItems = computed(() => this.items().filter((item) => item.active));
  readonly totalPrice = computed(() => this.items().reduce((sum, item) => sum + item.price, 0));

  readonly isAdmin = computed(() => this.currentUser()?.role === 'admin');
  readonly username = computed(() => this.currentUser()?.username ?? 'Guest');

  private readonly items$ = new BehaviorSubject<Item[]>(this.items());
  private readonly userChanged$ = new Subject<User>();
  readonly itemsObservable$: Observable<Item[]> = this.items$.asObservable();

  fetchItems(): Observable<Item[]> {
    return of(this.items()).pipe(delay(100));
  }

  fetchItemById(id: number): Observable<Item | undefined> {
    return this.fetchItems().pipe(map((items) => items.find((item) => item.id === id)));
  }

  getItemById(id: number): Item | undefined {
    return this.items().find((item) => item.id === id);
  }

  getItemsByCategory(category: string): Item[] {
    return this.items().filter((item) => item.category === category);
  }

  addItem(item: Omit<Item, 'id'>): void {
    const newId = Math.max(...this.items().map((i) => i.id)) + 1;
    this.items.update((current) => [...current, { ...item, id: newId }]);
    this.items$.next(this.items());
  }

  updateItem(id: number, updates: Partial<Item>): void {
    this.items.update((current) => current.map((item) => (item.id === id ? { ...item, ...updates } : item)));
    this.items$.next(this.items());
  }

  removeItem(id: number): void {
    this.items.update((current) => current.filter((item) => item.id !== id));
    this.items$.next(this.items());
  }

  toggleItemActive(id: number): void {
    this.items.update((current) =>
      current.map((item) => (item.id === id ? { ...item, active: !item.active } : item))
    );
  }

  setCurrentUser(user: User): void {
    this.currentUser.set(user);
    this.userChanged$.next(user);
  }

  clearCurrentUser(): void {
    this.currentUser.set(null);
  }

  setLoading(loading: boolean): void {
    this.isLoading.set(loading);
  }

  setError(error: string | null): void {
    this.error.set(error);
  }

  searchItems(query: string): Item[] {
    const lowerQuery = query.toLowerCase();
    return this.items().filter(
      (item) => item.name.toLowerCase().includes(lowerQuery) || item.description.toLowerCase().includes(lowerQuery)
    );
  }

  sortItemsByPrice(ascending = true): Item[] {
    return [...this.items()].sort((a, b) => (ascending ? a.price - b.price : b.price - a.price));
  }

  private internalMethod(): void {
    console.log('internal');
  }

  private _helperMethod(): string {
    return 'helper';
  }
}
