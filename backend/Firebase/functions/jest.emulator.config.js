/**
 * The suites that need a Firebase emulator running. `npm run test:emulator`
 * starts the database and Firestore emulators and runs them all;
 * `npm run test:rules` runs only the database rules suite. Plain `npm test`
 * skips them.
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
