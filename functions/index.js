const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.deleteMyAccountData = functions.https.onCall(async (data, context) => {
  if (!context.auth || !context.auth.uid) {
    throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");
  }

  const uid = context.auth.uid;
  const db = admin.firestore();

  const userRef = db.collection("users").doc(uid);

  // Deletes the document AND ALL nested subcollections recursively.
  // Works for any future subcollections you add under users/{uid}.
  await db.recursiveDelete(userRef);

  return { ok: true };
});
