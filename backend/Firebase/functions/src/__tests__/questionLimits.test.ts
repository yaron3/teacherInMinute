const mockReadRcNumber = jest.fn();

jest.mock("../remoteConfig", () => ({
  readRcNumber: (...args: unknown[]) => mockReadRcNumber(...args),
}));

import {
  DEFAULT_QUESTION_MAX_LENGTH,
  QUESTION_MAX_LENGTH_RC_KEY,
  getQuestionMaxLength,
} from "../questionLimits";

describe("getQuestionMaxLength", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test("uses the value Remote Config publishes", async () => {
    mockReadRcNumber.mockResolvedValue(2048);

    await expect(getQuestionMaxLength()).resolves.toBe(2048);
    expect(mockReadRcNumber).toHaveBeenCalledWith(QUESTION_MAX_LENGTH_RC_KEY);
  });

  test("falls back when the key is absent or unreadable", async () => {
    mockReadRcNumber.mockResolvedValue(undefined);

    await expect(getQuestionMaxLength()).resolves.toBe(DEFAULT_QUESTION_MAX_LENGTH);
  });

  // A published zero or negative would reject every question, so it is treated
  // as a mistake rather than as a limit.
  test.each([0, -50])("falls back on a published %p", async (published) => {
    mockReadRcNumber.mockResolvedValue(published);

    await expect(getQuestionMaxLength()).resolves.toBe(DEFAULT_QUESTION_MAX_LENGTH);
  });

  test("floors a fractional limit", async () => {
    mockReadRcNumber.mockResolvedValue(500.9);

    await expect(getQuestionMaxLength()).resolves.toBe(500);
  });
});
