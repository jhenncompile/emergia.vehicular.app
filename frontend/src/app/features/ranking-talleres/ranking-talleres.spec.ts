import { ComponentFixture, TestBed } from '@angular/core/testing';

import { RankingTalleres } from './ranking-talleres';

describe('RankingTalleres', () => {
  let component: RankingTalleres;
  let fixture: ComponentFixture<RankingTalleres>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [RankingTalleres],
    }).compileComponents();

    fixture = TestBed.createComponent(RankingTalleres);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
