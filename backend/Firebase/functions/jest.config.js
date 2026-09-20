/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  transform: {
    "^.+\\.tsx?$": ["ts-jest", { tsconfig: "tsconfig.test.json", diagnostics: false }],
  },
  testMatch: ["**/src/__tests__/**/*.test.ts"],
  // `*.emulator.test.ts` needs a running Firebase emulator, which this
  // command does not start. `npm run test:rules` runs those.
  testPathIgnorePatterns: ["/node_modules/", "\\.emulator\\.test\\.ts$"],
};
