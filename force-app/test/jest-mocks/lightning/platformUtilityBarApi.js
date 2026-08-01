import { createTestWireAdapter } from '@salesforce/wire-service-jest-util';

// Test double for lightning/platformUtilityBarApi.
export const EnclosingUtilityId = createTestWireAdapter(jest.fn());
export const getInfo = jest.fn(() => Promise.resolve({ utilityVisible: false }));
export const open = jest.fn(() => Promise.resolve(true));
export const minimize = jest.fn(() => Promise.resolve(true));
export const updateUtility = jest.fn(() => Promise.resolve(true));
export const updatePanel = jest.fn(() => Promise.resolve(true));
