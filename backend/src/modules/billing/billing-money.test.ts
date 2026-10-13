import { describe, expect, it } from 'vitest';
import { assertPaymentWithinBalance, roundMoney } from './billing.service';

describe('roundMoney', () => {
  it('rounds float sums to paise', () => {
    expect(roundMoney(0.1 + 0.2)).toBe(0.3);
    expect(roundMoney(5000.005)).toBe(5000.01);
    expect(roundMoney(1234.564)).toBe(1234.56);
  });
});

describe('assertPaymentWithinBalance', () => {
  it('accepts a payment up to the outstanding balance', () => {
    expect(() => assertPaymentWithinBalance(5000, 5000, 0)).not.toThrow();
    expect(() => assertPaymentWithinBalance(2000, 5000, 3000)).not.toThrow();
  });

  it('rejects an overpayment', () => {
    expect(() => assertPaymentWithinBalance(5000.01, 5000, 0)).toThrow(
      'Amount exceeds the outstanding balance of ₹5000.',
    );
    expect(() => assertPaymentWithinBalance(2500, 5000, 3000)).toThrow(
      'Amount exceeds the outstanding balance of ₹2000.',
    );
  });

  it('rejects any payment on a fully paid invoice', () => {
    expect(() => assertPaymentWithinBalance(1, 5000, 5000)).toThrow(
      'This invoice is already fully paid.',
    );
  });

  it('ignores float noise when comparing', () => {
    expect(() => assertPaymentWithinBalance(0.3, 0.1 + 0.2, 0)).not.toThrow();
  });
});
