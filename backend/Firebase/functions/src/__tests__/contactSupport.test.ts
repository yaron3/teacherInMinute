let settingsDoc: Record<string, unknown> | undefined;
jest.mock("firebase-admin", () => ({
  firestore: () => ({
    collection: () => ({ doc: () => ({ get: async () => ({ data: () => settingsDoc }) }) }),
  }),
}));

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

import {
  buildContactEmail,
  readContactRecipients,
  readSupportSettings,
  supportCaseUrl,
} from "../contactSupport";

describe("readContactRecipients", () => {
  const write = (content: string) => {
    const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "cs-")), "c.json");
    fs.writeFileSync(file, content);
    return file;
  };

  it("reads the list from the config file", () => {
    expect(readContactRecipients(write('{"contactRecipients":["a@x.com","b@x.com"]}'))).toEqual([
      "a@x.com",
      "b@x.com",
    ]);
  });

  it("falls back to the default when missing, empty or malformed", () => {
    expect(readContactRecipients("/nonexistent.json")).toEqual(["support@moreh-lerega.co.il"]);
    expect(readContactRecipients(write('{"contactRecipients":[]}'))).toEqual(["support@moreh-lerega.co.il"]);
    expect(readContactRecipients(write("not json"))).toEqual(["support@moreh-lerega.co.il"]);
  });

  it("ships a config whose default is support@moreh-lerega.co.il", () => {
    expect(readContactRecipients(path.join(__dirname, "..", "..", "support-config.json"))).toEqual([
      "support@moreh-lerega.co.il",
    ]);
  });
});

describe("readSupportSettings", () => {
  it("uses the config file until the console saves a list", async () => {
    settingsDoc = undefined;
    expect(await readSupportSettings()).toEqual({ recipients: ["support@moreh-lerega.co.il"], saved: false });
  });

  it("uses the saved list, dropping anything that is not an address", async () => {
    settingsDoc = { recipients: ["A@x.com", "nope", "b@x.com"] };
    expect(await readSupportSettings()).toEqual({ recipients: ["a@x.com", "b@x.com"], saved: true });
  });
});

describe("supportCaseUrl", () => {
  it("links to the case on the support page", () => {
    expect(supportCaseUrl("abc 1", "https://site.example/")).toBe("https://site.example/support.html?case=abc%201");
  });
});

describe("buildContactEmail", () => {
  it("marks a sample request from the admin console as a test", () => {
    expect(buildContactEmail({ title: "Hi", sample: true }).subject).toBe("[TEST] [Teacher in a Minute] Hi");
    expect(buildContactEmail({ title: "Hi" }).subject).toBe("[Teacher in a Minute] Hi");
  });

  it("opens with the case link when given one", () => {
    const { text } = buildContactEmail({ description: "Help" }, "https://site.example/support.html?case=1");
    expect(text.split("\n")[0]).toBe("Open the case to reply: https://site.example/support.html?case=1");
  });

  it("puts the title in the subject without newlines and the details in the body", () => {
    const { subject, text } = buildContactEmail({
      title: "Hi\r\nBcc: evil@x.com",
      description: "Help me",
      userName: "Dana",
      userEmail: "d@x.com",
    });
    expect(subject).not.toMatch(/[\r\n]/);
    expect(text).toContain("Help me");
    expect(text).toContain("Dana <d@x.com>");
  });
});
