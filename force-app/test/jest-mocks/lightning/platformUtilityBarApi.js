// Test double for lightning/platformUtilityBarApi.
export const openUtilityBar = jest.fn(() => Promise.resolve(true));
export const minimizeUtilityBar = jest.fn(() => Promise.resolve(true));
export const getUtilityBarAPI = jest.fn(() =>
    Promise.resolve({ openUtilityBar, minimizeUtilityBar })
);
