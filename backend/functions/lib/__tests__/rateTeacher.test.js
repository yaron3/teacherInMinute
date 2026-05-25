"use strict";
const txGet = jest.fn();
const txSet = jest.fn();
const runTransaction = jest.fn();
const collectionMock = jest.fn();
const adminFirestore = jest.fn();
const adminDatabase = jest.fn();
const dbRef = jest.fn();
const dbOnce = jest.fn();
let questionRef;
let teacherRef;
let ratingsCollectionRef;
let ratingRef;
let lessonRef;
let questionStatus;
let questionState;
jest.mock("firebase-functions/v2/https", () => ({
    onCall: (handler) => handler,
    HttpsError: class HttpsError extends Error {
        constructor(code, message) {
            super(message);
            this.code = code;
        }
    },
}));
jest.mock("firebase-functions/v2/tasks", () => ({
    onTaskDispatched: (handler) => handler,
}));
jest.mock("firebase-functions", () => ({
    logger: {
        info: jest.fn(),
        warn: jest.fn(),
        error: jest.fn(),
    },
}));
jest.mock("firebase-admin/functions", () => ({
    getFunctions: () => ({
        taskQueue: jest.fn(),
    }),
}));
jest.mock("../dispatch", () => ({
    backfillPendingQuestionsForTeacher: jest.fn(),
}));
jest.mock("firebase-admin", () => ({
    firestore: () => adminFirestore(),
    database: () => adminDatabase(),
}));
describe("rateTeacher", () => {
    beforeEach(() => {
        jest.resetModules();
        jest.clearAllMocks();
        questionRef = { path: "questions/question-1" };
        lessonRef = { path: "lessons/lesson-1" };
        questionStatus = "completed";
        questionState = undefined;
        ratingRef = { path: "teachers/teacher-1/ratings/question-1" };
        ratingsCollectionRef = {
            path: "teachers/teacher-1/ratings",
            doc: (id) => ({ path: `teachers/teacher-1/ratings/${id}` }),
        };
        teacherRef = {
            path: "teachers/teacher-1",
            collection: (name) => {
                if (name !== "ratings")
                    throw new Error(`Unexpected collection: ${name}`);
                return ratingsCollectionRef;
            },
        };
        collectionMock.mockImplementation((name) => {
            if (name === "questions") {
                return { doc: () => questionRef };
            }
            if (name === "teachers") {
                return { doc: () => teacherRef };
            }
            if (name === "lessons") {
                return { doc: () => lessonRef };
            }
            throw new Error(`Unexpected collection: ${name}`);
        });
        adminFirestore.mockReturnValue({
            collection: collectionMock,
            runTransaction,
        });
        dbOnce.mockResolvedValue({
            exists: () => false,
        });
        dbRef.mockReturnValue({
            once: dbOnce,
        });
        adminDatabase.mockReturnValue({
            ref: dbRef,
        });
        txGet.mockImplementation(async (ref) => {
            if (ref.path === questionRef.path) {
                return {
                    exists: true,
                    data: () => ({
                        studentUid: "student-1",
                        acceptedByTeacher: "teacher-1",
                        teacherUid: "teacher-1",
                        status: questionStatus,
                        state: questionState,
                        lessonId: "lesson-1",
                        startedAt: { started: true },
                        endedAt: { ended: true },
                    }),
                };
            }
            if (ref.path === lessonRef.path) {
                return {
                    exists: true,
                    data: () => ({
                        status: "completed",
                        startedAt: 1700000000000,
                        endedAt: 1700000300000,
                    }),
                };
            }
            if (ref.path === teacherRef.path) {
                return {
                    exists: true,
                    data: () => ({ averageRate: 4 }),
                };
            }
            if (ref.path === ratingRef.path) {
                return { exists: false };
            }
            if (ref.path === ratingsCollectionRef.path) {
                return { size: 2 };
            }
            throw new Error(`Unexpected ref in tx.get: ${ref.path}`);
        });
        txSet.mockResolvedValue(undefined);
        runTransaction.mockImplementation(async (handler) => {
            await handler({ get: txGet, set: txSet });
        });
    });
    test("stores a student rating and updates the teacher average", async () => {
        const { rateTeacher } = await Promise.resolve().then(() => require("../lessons"));
        const callRateTeacher = rateTeacher;
        const result = await callRateTeacher({
            auth: { uid: "student-1" },
            data: {
                questionId: "question-1",
                teacherId: "teacher-1",
                rating: 5,
            },
        });
        expect(result).toEqual({ success: true });
        expect(runTransaction).toHaveBeenCalledTimes(1);
        expect(dbRef).toHaveBeenCalledWith("questions/question-1");
        expect(dbOnce).toHaveBeenCalledWith("value");
        expect(txSet).toHaveBeenNthCalledWith(1, expect.objectContaining({ path: ratingRef.path }), expect.objectContaining({
            studentId: "student-1",
            studentRate: 5,
        }));
        expect(txSet).toHaveBeenNthCalledWith(2, expect.objectContaining({ path: teacherRef.path }), expect.objectContaining({ averageRate: 4.333333333333333 }), { merge: true });
    });
    test("rejects non-integer ratings", async () => {
        const { rateTeacher } = await Promise.resolve().then(() => require("../lessons"));
        const callRateTeacher = rateTeacher;
        await expect(callRateTeacher({
            auth: { uid: "student-1" },
            data: {
                questionId: "question-1",
                teacherId: "teacher-1",
                rating: 4.5,
            },
        })).rejects.toMatchObject({ code: "invalid-argument" });
        expect(runTransaction).not.toHaveBeenCalled();
    });
    test("rejects rating while RTDB question still exists", async () => {
        const { rateTeacher } = await Promise.resolve().then(() => require("../lessons"));
        const callRateTeacher = rateTeacher;
        dbOnce.mockResolvedValueOnce({
            exists: () => true,
        });
        await expect(callRateTeacher({
            auth: { uid: "student-1" },
            data: {
                questionId: "question-1",
                teacherId: "teacher-1",
                rating: 5,
            },
        })).rejects.toMatchObject({ code: "failed-precondition" });
        expect(runTransaction).not.toHaveBeenCalled();
    });
    test("accepts rating when lesson is completed even if question status lags", async () => {
        const { rateTeacher } = await Promise.resolve().then(() => require("../lessons"));
        const callRateTeacher = rateTeacher;
        questionStatus = "in_progress";
        questionState = undefined;
        const result = await callRateTeacher({
            auth: { uid: "student-1" },
            data: {
                questionId: "question-1",
                teacherId: "teacher-1",
                rating: 5,
            },
        });
        expect(result).toEqual({ success: true });
        expect(runTransaction).toHaveBeenCalledTimes(1);
    });
});
//# sourceMappingURL=rateTeacher.test.js.map