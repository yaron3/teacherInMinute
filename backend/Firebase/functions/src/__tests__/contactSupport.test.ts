jest.mock("firebase-admin", () => ({ firestore: () => ({}) }));

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

import { buildContactEmail, readContactRecipients } from "../contactSupport";

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
    expect(readContactRecipients("/nonexistent.json")).toEqual(["yaron@yaronj.com"]);
    expect(readContactRecipients(write('{"contactRecipients":[]}'))).toEqual(["yaron@yaronj.com"]);
    expect(readContactRecipients(write("not json"))).toEqual(["yaron@yaronj.com"]);
  });

  it("ships a config whose default is yaron@yaronj.com", () => {
    expect(readContactRecipients(path.join(__dirname, "..", "..", "support-config.json"))).toEqual([
      "yaron@yaronj.com",
    ]);
  });
});

describe("buildContactEmail", () => {
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
