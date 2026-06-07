import { Injectable } from '@angular/core';
import { Subject } from 'rxjs';

export interface ToastMessage {
  id: string;
  title: string;
  message: string;
  type: 'info' | 'success' | 'warning' | 'error';
}

@Injectable({ providedIn: 'root' })
export class ToastService {
  private toastsSubject = new Subject<ToastMessage>();
  public toasts$ = this.toastsSubject.asObservable();

  show(title: string, message: string, type: 'info' | 'success' | 'warning' | 'error' = 'info') {
    this.toastsSubject.next({ id: Math.random().toString(36).substring(2, 9), title, message, type });
  }
}
