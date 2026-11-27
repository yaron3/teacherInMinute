import { doc, setDoc } from "firebase/firestore";
import { ref, uploadBytes } from "firebase/storage";
import { firestore, storage } from "./firebase";

// Contact support, as ContactSupportService does on the apps: images go to
// `contactAttachments/{uid}/{id}/{index}.jpg` first, then the request is
// written to `contactRequests/{id}`, whose creation emails support (the
// backend's trigger reads the images back by index). firestore.rules and
// storage.rules hold the limits below.

export const TITLE_MAX = 50;
export const DESCRIPTION_MAX = 1024;
export const MAX_ATTACHMENTS = 3;
/** The longer side an image is scaled to: enough to read a full-height screenshot. */
const ATTACHMENT_MAX_DIMENSION = 2400;

export interface SupportRequest {
  id: string;
  title: string;
  description: string;
  userId: string;
  userName: string;
  userEmail: string;
  /** ISO 8601, as ISO8601DateFormatter writes it. */
  sentAt: string;
  deviceType: string;
  osVersion: string;
  locale: string;
  role: "student" | "teacher";
  attachmentCount?: number;
}

/** "Chrome 131 on Windows", from the browser's own report. */
function browserDescription(): string {
  const ua = navigator.userAgent;
  const browser =
    /Edg\/(\d+)/.exec(ua)?.[1] ? `Edge ${/Edg\/(\d+)/.exec(ua)![1]}`
    : /Chrome\/(\d+)/.exec(ua)?.[1] ? `Chrome ${/Chrome\/(\d+)/.exec(ua)![1]}`
    : /Firefox\/(\d+)/.exec(ua)?.[1] ? `Firefox ${/Firefox\/(\d+)/.exec(ua)![1]}`
    : /Version\/(\d+).*Safari/.exec(ua)?.[1] ? `Safari ${/Version\/(\d+).*Safari/.exec(ua)![1]}`
    : "Browser";
  const os =
    /Windows/.test(ua) ? "Windows"
    : /Mac OS X/.test(ua) ? "macOS"
    : /Android/.test(ua) ? "Android"
    : /iPhone|iPad/.test(ua) ? "iOS"
    : /Linux/.test(ua) ? "Linux"
    : "unknown OS";
  return `${browser} on ${os}`;
}

export function makeRequest(fields: {
  title: string;
  description: string;
  userId: string;
  userName: string;
  userEmail: string;
  locale: string;
  attachmentCount: number;
  role: "student" | "teacher";
}): SupportRequest {
  const request: SupportRequest = {
    id: crypto.randomUUID().toUpperCase(),
    title: fields.title.trim(),
    description: fields.description.trim(),
    userId: fields.userId,
    userName: fields.userName,
    userEmail: fields.userEmail,
    sentAt: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    // Installed from the browser, the app runs as a PWA; this tells support so.
    deviceType: window.matchMedia("(display-mode: standalone)").matches ? "Web app" : "Web",
    osVersion: browserDescription(),
    locale: fields.locale,
    role: fields.role,
  };
  // Only with images, as on the apps.
  if (fields.attachmentCount > 0) request.attachmentCount = fields.attachmentCount;
  return request;
}

/** A picked image as a JPEG no larger than the apps send. */
export async function toJpeg(file: File): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, ATTACHMENT_MAX_DIMENSION / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  const g = canvas.getContext("2d")!;
  g.fillStyle = "#fff"; // a transparent PNG would otherwise turn black
  g.fillRect(0, 0, canvas.width, canvas.height);
  g.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  return new Promise((resolve, reject) =>
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error("could not encode image"))), "image/jpeg", 0.85),
  );
}

/** Uploads the images, then writes the request that counts them. */
export async function sendRequest(request: SupportRequest, images: Blob[]): Promise<void> {
  for (const [index, image] of images.slice(0, MAX_ATTACHMENTS).entries()) {
    await uploadBytes(ref(storage, `contactAttachments/${request.userId}/${request.id}/${index}.jpg`), image, {
      contentType: "image/jpeg",
    });
  }
  await setDoc(doc(firestore, "contactRequests", request.id), request);
}
