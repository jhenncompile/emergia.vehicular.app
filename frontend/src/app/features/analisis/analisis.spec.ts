import { ComponentFixture, TestBed } from '@angular/core/testing';

import { Analisis } from './analisis';

describe('Analisis', () => {
  let component: Analisis;
  let fixture: ComponentFixture<Analisis>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [Analisis],
    }).compileComponents();

    fixture = TestBed.createComponent(Analisis);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
