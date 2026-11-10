const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

async function tokensFor(uids) {
  const tokens = [];
  for (const uid of uids) {
    const snap = await db.collection("users").doc(uid).get();
    const t = snap.get("fcmToken");
    if (t) tokens.push(t);
  }
  return tokens;
}

// New chat message -> notify the other members.
exports.onNewMessage = onDocumentCreated("rooms/{roomId}/messages/{msgId}", async (event) => {
  const msg = event.data.data();
  const roomId = event.params.roomId;
  const room = (await db.collection("rooms").doc(roomId).get()).data() || {};

  let recipients;
  if (room.type === "dm") {
    recipients = (room.members || []).filter((uid) => uid !== msg.senderId);
  } else {
    // Group rooms: MVP sends to every user except the sender.
    const users = await db.collection("users").get();
    recipients = users.docs.map((d) => d.id).filter((uid) => uid !== msg.senderId);
  }

  const tokens = await tokensFor(recipients);
  if (tokens.length === 0) return;

  const body = msg.type === "AUDIO" ? "رسالة صوتية" : msg.text || "";
  await messaging.sendEachForMulticast({
    tokens,
    notification: { title: msg.senderName || "Vexo", body },
    data: { type: "message", roomId },
  });
});

// New call ringing -> notify the callee.
exports.onIncomingCall = onDocumentCreated("calls/{callId}", async (event) => {
  const call = event.data.data();
  if (call.status !== "ringing") return;

  const tokens = await tokensFor([call.calleeId]);
  if (tokens.length === 0) return;

  await messaging.sendEachForMulticast({
    tokens,
    notification: {
      title: call.video ? "مكالمة فيديو واردة" : "مكالمة واردة",
      body: call.callerName || "Vexo",
    },
    data: { type: "call", callId: event.params.callId },
    android: { priority: "high" },
    apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
  });
});
