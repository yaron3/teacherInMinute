import { useEffect, useState } from "react";
import { useStrings } from "../i18n";
import { STUDENT_GRADES, updateProfile, type StudentProfile } from "../services/account";
import { auth } from "../services/firebase";
import { fetchTeacherDetails, type TeacherDetails } from "../services/teacher";
import { TeacherSubjects } from "./TeacherSubjects";

type Save = "idle" | "saving" | "saved" | "failed";

/** The ISO date-time the apps store, as an `<input type="date">` value. */
const toDateInput = (iso: string) => (iso ? iso.slice(0, 10) : "");
/** Back to the apps' ISO form: midnight UTC on that day. */
const fromDateInput = (value: string) => (value ? new Date(`${value}T00:00:00Z`).toISOString().replace(".000Z", "Z") : "");

/** The student's own details (ProfileView): name, phone, grade and date of
 *  birth are editable; the email is the sign-in and stays as it is. */
export function ProfileScreen({ profile }: { profile: StudentProfile | null }) {
  const { t } = useStrings();
  const [fullName, setFullName] = useState("");
  const [phoneNumber, setPhoneNumber] = useState("");
  const [grade, setGrade] = useState("");
  const [birth, setBirth] = useState("");
  const [save, setSave] = useState<Save>("idle");
  const [loadedFor, setLoadedFor] = useState("");
  const isTeacher = profile?.role === "teacher";
  const [teacher, setTeacher] = useState<TeacherDetails | null>(null);
  const [editingSubjects, setEditingSubjects] = useState(false);
  const [subjectsVersion, setSubjectsVersion] = useState(0);
  useEffect(() => {
    const uid = auth.currentUser?.uid;
    if (!isTeacher || !uid) return;
    fetchTeacherDetails(uid).then(setTeacher, (e) => console.error("[profile] teacher details failed", e));
  }, [isTeacher, subjectsVersion]);

  // Fill the form once per profile load, not on every live update, so an
  // edit in progress is not overwritten.
  useEffect(() => {
    if (!profile) return;
    const key = auth.currentUser?.uid ?? "";
    if (loadedFor === key) return;
    setLoadedFor(key);
    setFullName(profile.fullName);
    setPhoneNumber(profile.phoneNumber);
    setGrade(profile.grade);
    setBirth(toDateInput(profile.dateOfBirth));
  }, [profile, loadedFor]);

  const changed =
    !!profile &&
    (fullName.trim() !== profile.fullName ||
      phoneNumber.trim() !== profile.phoneNumber ||
      grade !== profile.grade ||
      birth !== toDateInput(profile.dateOfBirth));
  const valid = fullName.trim().length >= 2;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const uid = auth.currentUser?.uid;
    if (!uid || !changed || !valid) return;
    setSave("saving");
    try {
      await updateProfile(uid, { fullName, phoneNumber, grade, dateOfBirth: fromDateInput(birth) });
      setSave("saved");
    } catch (err) {
      console.error("[profile] save failed", err);
      setSave("failed");
    }
  };

  const initials = (profile?.fullName || "?").trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join("").toUpperCase();

  return (
    <section className="page">
      <h2 className="page-title">{t.profileTitle}</h2>
      <div className="profile-head">
        {profile?.photoUrl ? <img className="profile-photo" src={profile.photoUrl} alt="" /> : <div className="profile-photo">{initials}</div>}
        <div>
          <strong dir="auto">{profile?.fullName}</strong>
          <div className="muted small">
            {isTeacher
              ? `${t.teacherRole} · ${teacher ? (teacher.verified ? t.verified : t.pendingVerificationShort) : ""}`
              : `${t.studentRole} · ${t.minutesLeft(profile?.remainingMinutes ?? 0)}`}
          </div>
        </div>
      </div>

      <form className="card form" onSubmit={submit}>
        <label>
          <span className="label">{t.fullName}</span>
          <input dir="auto" value={fullName} onChange={(e) => { setFullName(e.target.value); setSave("idle"); }} autoComplete="name" />
        </label>
        <label>
          <span className="label">{t.email}</span>
          <input value={profile?.email ?? ""} readOnly disabled dir="ltr" />
        </label>
        <label>
          <span className="label">{t.phone}</span>
          <input type="tel" dir="ltr" value={phoneNumber} onChange={(e) => { setPhoneNumber(e.target.value); setSave("idle"); }} autoComplete="tel" />
        </label>
        {!isTeacher && (
        <label>
          <span className="label">{t.grade}</span>
          <select value={grade} onChange={(e) => { setGrade(e.target.value); setSave("idle"); }}>
            <option value="">{t.chooseGrade}</option>
            {STUDENT_GRADES.map((g) => (
              <option key={g} value={g}>
                {t.grades[g] ?? g}
              </option>
            ))}
            {grade && !STUDENT_GRADES.includes(grade) && <option value={grade}>{grade}</option>}
          </select>
        </label>
        )}
        {!isTeacher && (
        <label>
          <span className="label">{t.dateOfBirth}</span>
          <input type="date" value={birth} max={new Date().toISOString().slice(0, 10)} onChange={(e) => { setBirth(e.target.value); setSave("idle"); }} />
        </label>
        )}
        <div className="form-actions">
          {save === "saved" && <span className="ok-text">{t.saved}</span>}
          {save === "failed" && <span className="error">{t.genericError}</span>}
          <button className="primary" type="submit" disabled={!changed || !valid || save === "saving"}>
            {save === "saving" ? t.saving : t.save}
          </button>
        </div>
      </form>

      {isTeacher && teacher && editingSubjects && (
        <TeacherSubjects
          current={teacher.subjectSelections}
          onCancel={() => setEditingSubjects(false)}
          onSaved={() => {
            setEditingSubjects(false);
            setSubjectsVersion((v) => v + 1);
          }}
        />
      )}
      {isTeacher && !editingSubjects && (
        <div className="card form">
          <div className="subject-area-head">
            <h3 className="section-title">{t.mySubjects}</h3>
            {teacher && (
              <button className="secondary small" onClick={() => setEditingSubjects(true)}>
                {t.editSubjects}
              </button>
            )}
          </div>
          {teacher === null ? (
            <div className="pulse small-pulse" />
          ) : Object.keys(teacher.subjectSelections).length === 0 ? (
            <p className="muted">{t.noSubjects}</p>
          ) : (
            Object.entries(teacher.subjectSelections).map(([area, keys]) => (
              <div key={area} className="subject-area">
                <strong>{t.subjectAreas[area] ?? area}</strong>
                <div className="chips">
                  {keys.map((k) => (
                    <span key={k} className="chip static">
                      {t.topics[k.toLowerCase() as keyof typeof t.topics] ?? k}
                    </span>
                  ))}
                </div>
              </div>
            ))
          )}
        </div>
      )}
    </section>
  );
}
