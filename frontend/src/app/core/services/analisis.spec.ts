import { TestBed } from '@angular/core/testing';

import { Analisis } from './analisis';

describe('Analisis', () => {
  let service: Analisis;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(Analisis);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
