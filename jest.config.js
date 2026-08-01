const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    moduleNameMapper: {
        '^lightning/platformShowToastEvent$':
            '<rootDir>/force-app/test/jest-mocks/lightning/platformShowToastEvent',
        '^lightning/platformUtilityBarApi$':
            '<rootDir>/force-app/test/jest-mocks/lightning/platformUtilityBarApi',
        '^lightning/empApi$': '<rootDir>/force-app/test/jest-mocks/lightning/empApi',
        '^lightning/navigation$': '<rootDir>/force-app/test/jest-mocks/lightning/navigation'
    }
};
