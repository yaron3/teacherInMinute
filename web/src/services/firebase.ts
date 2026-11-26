import { initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth } from "firebase/auth";
import { connectDatabaseEmulator, getDatabase } from "firebase/database";
import { connectFirestoreEmulator, getFirestore } from "firebase/firestore";
import { connectFunctionsEmulator, getFunctions } from "firebase/functions";
import { connectStorageEmulator, getStorage } from "firebase/storage";

const env = import.meta.env;
const projectId = env.VITE_FIREBASE_PROJECT_ID || "demo-teacher-in-a-moment";

export const usingEmulators = env.VITE_USE_EMULATORS === "true";

// Against the emulators only the project id matters; the rest are placeholders
// the SDK insists on. Against a real project they come from a registered Web
// app (see .env.example).
const app = initializeApp({
  apiKey: env.VITE_FIREBASE_API_KEY || "emulator-placeholder",
  authDomain: env.VITE_FIREBASE_AUTH_DOMAIN || `${projectId}.firebaseapp.com`,
  // In the emulator the Admin SDK writes to a namespace named after the bare
  // project id (no `-default-rtdb`), and the client reads whichever namespace
  // this URL's subdomain names, so the two have to agree.
  databaseURL: env.VITE_FIREBASE_DATABASE_URL || `https://${projectId}.firebaseio.com`,
  storageBucket: env.VITE_FIREBASE_STORAGE_BUCKET || `${projectId}.appspot.com`,
  appId: env.VITE_FIREBASE_APP_ID || "1:000000000000:web:emulator",
  projectId,
});

export const auth = getAuth(app);
export const firestore = getFirestore(app);
export const database = getDatabase(app);
// The backend sets no region, so every callable lives in us-central1.
export const functions = getFunctions(app, "us-central1");
export const storage = getStorage(app);

if (usingEmulators) {
  // Ports from backend/Firebase/firebase.json.
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  connectFirestoreEmulator(firestore, "127.0.0.1", 8085);
  connectDatabaseEmulator(database, "127.0.0.1", 9000);
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  connectStorageEmulator(storage, "127.0.0.1", 9199);
}
