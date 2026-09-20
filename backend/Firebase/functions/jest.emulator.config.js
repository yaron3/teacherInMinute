/**
 * The suites that need a Firebase emulator running. `npm run test:rules` starts
 * one and points this at it; plain `npm test` skips them.
 *
 * @type {import('jest').Config}
 */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  transform: {
    "^.+\\.tsx?$": ["ts-jest", { tsconfig: "tsconfig.test.json", diagnostics: false }],
  },
  testMatch: ["**/src/__tests__/**/*.emulator.test.ts"],
};
