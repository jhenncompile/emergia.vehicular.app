import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { environment } from '../../../environments/environment';

export interface SyncTask {
  id: string;
  url: string;
  method: 'POST' | 'PUT' | 'PATCH';
  body: any;
  incidenteId: number; // Para marcar la UI
}

@Injectable({
  providedIn: 'root'
})
export class SyncWebService {
  private readonly QUEUE_KEY = 'vialia_sync_queue';
  
  private isOnlineSubject = new BehaviorSubject<boolean>(navigator.onLine);
  public isOnline$ = this.isOnlineSubject.asObservable();

  private queueSubject = new BehaviorSubject<SyncTask[]>(this.getQueue());
  public queue$ = this.queueSubject.asObservable();

  constructor(private http: HttpClient) {
    window.addEventListener('online', () => {
      this.isOnlineSubject.next(true);
      this.syncQueue();
    });
    window.addEventListener('offline', () => {
      this.isOnlineSubject.next(false);
    });
  }

  get isOnline(): boolean {
    return this.isOnlineSubject.value;
  }

  private getQueue(): SyncTask[] {
    const data = localStorage.getItem(this.QUEUE_KEY);
    return data ? JSON.parse(data) : [];
  }

  private saveQueue(queue: SyncTask[]) {
    localStorage.setItem(this.QUEUE_KEY, JSON.stringify(queue));
    this.queueSubject.next(queue);
  }

  enqueueTask(url: string, method: 'POST' | 'PUT' | 'PATCH', body: any, incidenteId: number) {
    const queue = this.getQueue();
    queue.push({
      id: Math.random().toString(36).substring(2, 9),
      url,
      method,
      body,
      incidenteId
    });
    this.saveQueue(queue);
  }

  hasPendingTask(incidenteId: number): boolean {
    return this.getQueue().some(t => t.incidenteId === incidenteId);
  }

  async syncQueue() {
    const queue = this.getQueue();
    if (queue.length === 0) return;

    const token = localStorage.getItem('token');
    const headers = new HttpHeaders().set('Authorization', `Bearer ${token}`);
    
    let successfulCount = 0;
    let newQueue = [...queue];

    for (const task of queue) {
      try {
        if (task.method === 'POST') {
          await this.http.post(task.url, task.body, { headers }).toPromise();
        } else if (task.method === 'PUT') {
          await this.http.put(task.url, task.body, { headers }).toPromise();
        } else if (task.method === 'PATCH') {
          await this.http.patch(task.url, task.body, { headers }).toPromise();
        }
        
        // Si no dio error, lo sacamos de la cola
        newQueue = newQueue.filter(t => t.id !== task.id);
        successfulCount++;
      } catch (err) {
        console.error('Error sincronizando task', task, err);
        // Si es 401 o 403, tal vez abortar. Pero dejaremos que se quede en cola por ahora o lo descartamos según convenga.
      }
    }

    this.saveQueue(newQueue);
    
    if (successfulCount > 0) {
      alert(`Conexión recuperada. ${successfulCount} cambios sincronizados con éxito. ✅`);
    }
  }
}
