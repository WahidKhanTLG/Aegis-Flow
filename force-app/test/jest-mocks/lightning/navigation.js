import { createTestWireAdapter } from '@salesforce/wire-service-jest-util';
export const CurrentPageReference = createTestWireAdapter(jest.fn());
export const NavigationMixin = (Base) => class extends Base {
    [Symbol.for('Navigate')]() {}
    [Symbol.for('GenerateUrl')]() { return Promise.resolve('/'); }
};
NavigationMixin.Navigate = Symbol.for('Navigate');
NavigationMixin.GenerateUrl = Symbol.for('GenerateUrl');
