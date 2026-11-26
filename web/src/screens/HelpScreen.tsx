import { useEffect, useRef, useState } from "react";
import { useStrings } from "../i18n";
import type { StudentProfile } from "../services/account";
import { auth } from "../services/firebase";
import { LegalLink } from "./LegalViewer";
import {
  DESCRIPTION_MAX,
  MAX_ATTACHMENTS,
  TITLE_MAX,
  makeRequest,
  sendRequest,
  toJpeg,
  type SupportRequest,
} from "../services/support";

interface Attachment {
  blob: Blob;
  url: string;
}

type Send = "idle" | "sending" | "sent" | "failed";

/** Help & Support (HelpSupportView): the contact form, previewed before it is
 *  sent, with up to three images. */
export function HelpScreen({ profile }: { profile: StudentProfile | null }) {
  const { t, language } = useStrings();
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const [imageError, setImageError] = useState(false);
  const [preview, setPreview] = useState<SupportRequest | null>(null);
  const [send, setSend] = useState<Send>("idle");
  const picker = useRef<HTMLInputElement>(null);

  // Thumbnails hold object URLs; let them go with the page.
  const urls = useRef<string[]>([]);
  urls.current = attachments.map((a) => a.url);
  useEffect(() => () => urls.current.forEach((u) => URL.revokeObjectURL(u)), []);

  const canPreview = title.trim().length > 0 && description.trim().length > 0 && send !== "sending";

  const addImages = async (files: FileList | null) => {
    setImageError(false);
    const room = MAX_ATTACHMENTS - attachments.length;
    const picked = Array.from(files ?? []).slice(0, room);
    const added: Attachment[] = [];
    for (const file of picked) {
      try {
        const blob = await toJpeg(file);
        added.push({ blob, url: URL.createObjectURL(blob) });
      } catch (e) {
        console.error("[support] image read failed", e);
        setImageError(true);
      }
    }
    setAttachments((list) => [...list, ...added].slice(0, MAX_ATTACHMENTS));
    if (picker.current) picker.current.value = "";
  };

  const remove = (index: number) => {
    setAttachments((list) => {
      URL.revokeObjectURL(list[index].url);
      return list.filter((_, i) => i !== index);
    });
  };

  const openPreview = (e: React.FormEvent) => {
    e.preventDefault();
    const user = auth.currentUser;
    if (!canPreview || !user) return;
    setSend("idle");
    setPreview(
      makeRequest({
        title,
        description,
        userId: user.uid,
        userName: profile?.fullName ?? "",
        userEmail: profile?.email || user.email || "",
        locale: language === "hebrew" ? "he_IL" : "en_US",
        attachmentCount: attachments.length,
        role: profile?.role === "teacher" ? "teacher" : "student",
      }),
    );
  };

  const submit = async () => {
    if (!preview) return;
    setSend("sending");
    try {
      await sendRequest(preview, attachments.map((a) => a.blob));
      setSend("sent");
      setPreview(null);
      setTitle("");
      setDescription("");
      attachments.forEach((a) => URL.revokeObjectURL(a.url));
      setAttachments([]);
    } catch (e) {
      console.error("[support] send failed", e);
      setSend("failed");
    }
  };

  const locale = language === "hebrew" ? "he-IL" : "en-US";
  const rows: [string, string][] = preview
    ? [
        [t.supportFields.title, preview.title],
        [t.supportFields.description, preview.description],
        ...(preview.attachmentCount ? ([[t.supportFields.attachments, String(preview.attachmentCount)]] as [string, string][]) : []),
        [t.supportFields.userId, preview.userId],
        [t.supportFields.sentAt, new Date(preview.sentAt).toLocaleString(locale, { dateStyle: "medium", timeStyle: "short" })],
        [t.supportFields.deviceType, preview.deviceType],
        [t.supportFields.osVersion, preview.osVersion],
        [t.supportFields.locale, preview.locale],
      ]
    : [];

  return (
    <section className="page">
      <h2 className="page-title">{t.navHelp}</h2>
      <p className="muted">{t.helpIntro}</p>

      {send === "sent" && (
        <div className="notice ok" role="status">
          {t.supportSent}
        </div>
      )}

      <form className="card form support-form" onSubmit={openPreview}>
        <label>
          <span className="label">{t.supportTitle}</span>
          <input
            dir="auto"
            value={title}
            maxLength={TITLE_MAX}
            placeholder={t.supportTitlePlaceholder}
            onChange={(e) => {
              setTitle(e.target.value);
              if (send === "sent") setSend("idle");
            }}
          />
          <span className="counter">
            {title.length}/{TITLE_MAX}
          </span>
        </label>
        <label>
          <span className="label">{t.supportDescription}</span>
          <textarea dir="auto" rows={7} value={description} maxLength={DESCRIPTION_MAX} onChange={(e) => setDescription(e.target.value)} />
          <span className="counter">
            {description.length}/{DESCRIPTION_MAX}
          </span>
        </label>

        <div className="attachments">
          <span className="label">{t.supportAttachments}</span>
          <span className="muted small">{t.supportAttachmentsHint}</span>
          <div className="attachment-row">
            {attachments.map((a, i) => (
              <div key={a.url} className="attachment">
                <img src={a.url} alt="" />
                <button type="button" className="remove" onClick={() => remove(i)} aria-label={t.removeImage} title={t.removeImage}>
                  ✕
                </button>
              </div>
            ))}
            {attachments.length < MAX_ATTACHMENTS && (
              <button type="button" className="attachment add" onClick={() => picker.current?.click()} aria-label={t.addImage} title={t.addImage}>
                ＋
              </button>
            )}
          </div>
          <span className="counter">
            {attachments.length}/{MAX_ATTACHMENTS}
          </span>
          {imageError && <span className="error small">{t.imageFailed}</span>}
          <input ref={picker} type="file" accept="image/*" multiple hidden onChange={(e) => void addImages(e.target.files)} />
        </div>

        <div className="form-actions">
          <button className="primary" type="submit" disabled={!canPreview}>
            {t.previewAndSubmit}
          </button>
        </div>
      </form>

      <div className="card legal">
        <h3>{t.legalTitle}</h3>
        <LegalLink page="eula">{t.termsOfService}</LegalLink>
        <LegalLink page="privacy">{t.privacyPolicy}</LegalLink>
      </div>

      {preview && (
        <div className="scrim" role="dialog" aria-modal="true" aria-label={t.dataToBeSent}>
          <div className="dialog details">
            <h3>{t.dataToBeSent}</h3>
            <dl>
              {rows.map(([k, v]) => (
                <div key={k} className="dl-row">
                  <dt>{k}</dt>
                  <dd dir="auto">{v}</dd>
                </div>
              ))}
            </dl>
            {attachments.length > 0 && (
              <div className="attachment-row">
                {attachments.map((a) => (
                  <div key={a.url} className="attachment small">
                    <img src={a.url} alt="" />
                  </div>
                ))}
              </div>
            )}
            {send === "failed" && <p className="error">{t.supportFailed}</p>}
            <div className="dialog-actions">
              <button className="secondary" onClick={() => setPreview(null)} disabled={send === "sending"}>
                {t.cancel}
              </button>
              <button className="primary" onClick={submit} disabled={send === "sending"}>
                {send === "sending" ? t.sending : t.submit}
              </button>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
