import { readFileSync } from "fs";
import { resolve } from "path";
import { runInNewContext } from "vm";

function page() {
  const elements = new Map<string, any>();
  const element = (id: string): any => {
    if (!elements.has(id)) {
      const classes = new Set(id === "view-success" ? ["hidden"] : []);
      elements.set(id, {
        value: "", disabled: false, checked: false, textContent: "", open: false,
        listeners: {} as any,
        classList: { add: (name: string) => classes.add(name), remove: (name: string) => classes.delete(name), contains: (name: string) => classes.has(name) },
        addEventListener(name: string, fn: any) { this.listeners[name] = fn; },
        showModal() { this.open = true; }, close() { this.open = false; this.listeners.close?.(); },
        focus: jest.fn(),
      });
    }
    return elements.get(id);
  };
  const user = { email: "owner@example.com", getIdToken: jest.fn().mockResolvedValue("token") };
  const auth = { setPersistence: jest.fn(), signInWithEmailAndPassword: jest.fn().mockResolvedValue({ user }), signOut: jest.fn() };
  const deleteAccount = jest.fn().mockResolvedValue({ data: { deleted: true } });
  const firebase = { initializeApp: jest.fn(), auth: Object.assign(() => auth, { Auth: { Persistence: { NONE: "none" } } }), functions: () => ({ httpsCallable: () => deleteAccount }) };
  const html = readFileSync(resolve(__dirname, "../../../public/deleteAccount.html"), "utf8");
  const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)![1];
  runInNewContext(script, { document: { getElementById: element }, firebase });
  element("email").value = "owner@example.com";
  element("password").value = "test-password";
  return { element, auth, deleteAccount, submit: () => element("login-form").listeners.submit({ preventDefault() {} }) };
}
it("opens the warning only after verifying credentials and clears the password", async () => {
  const p = page();
  await p.submit();
  expect(p.auth.signInWithEmailAndPassword).toHaveBeenCalledWith("owner@example.com", "test-password");
  expect(p.element("delete-dialog").open).toBe(true);
  expect(p.element("password").value).toBe("");
  expect(p.element("delete-button").disabled).toBe(true);
  expect(p.deleteAccount).not.toHaveBeenCalled();
});
it("never opens confirmation or deletes after invalid credentials", async () => {
  const p = page();
  p.auth.signInWithEmailAndPassword.mockRejectedValueOnce({ code: "auth/invalid-credential" });
  await p.submit();
  expect(p.element("delete-dialog").open).toBe(false);
  expect(p.element("login-error").textContent).toContain("Could not verify");
  expect(p.deleteAccount).not.toHaveBeenCalled();
});
it("cancels without deleting", async () => {
  const p = page();
  await p.submit();
  p.element("cancel-button").listeners.click();
  expect(p.element("delete-dialog").open).toBe(false);
  expect(p.auth.signOut).toHaveBeenCalled();
  expect(p.deleteAccount).not.toHaveBeenCalled();
});
it("requires acknowledgement, then reports success only after backend completion", async () => {
  const p = page();
  await p.submit();
  await p.element("delete-button").listeners.click();
  expect(p.deleteAccount).not.toHaveBeenCalled();
  p.element("acknowledge").checked = true;
  await p.element("delete-button").listeners.click();
  expect(p.deleteAccount).toHaveBeenCalledWith({ confirmDeletion: true });
  expect(p.element("view-success").classList.contains("hidden")).toBe(false);
});
it("keeps the dialog open and shows an error when deletion fails", async () => {
  const p = page();
  await p.submit();
  p.element("acknowledge").checked = true;
  p.deleteAccount.mockRejectedValueOnce({ code: "functions/internal" });
  await p.element("delete-button").listeners.click();
  expect(p.element("delete-dialog").open).toBe(true);
  expect(p.element("view-success").classList.contains("hidden")).toBe(true);
  expect(p.element("delete-button").disabled).toBe(false);
});
