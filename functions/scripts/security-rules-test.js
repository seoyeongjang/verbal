const fs = require("node:fs");
const path = require("node:path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  deleteDoc,
  collection,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  setDoc,
  serverTimestamp,
  where,
} = require("firebase/firestore");
const {
  deleteObject,
  getDownloadURL,
  ref,
  uploadString,
} = require("firebase/storage");

const rootDir = path.resolve(__dirname, "..", "..");
const projectId = process.env.GCLOUD_PROJECT || "demo-verbal";

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(
        path.join(rootDir, "firebase", "firestore.rules"),
        "utf8",
      ),
    },
    storage: {
      rules: fs.readFileSync(
        path.join(rootDir, "firebase", "storage.rules"),
        "utf8",
      ),
    },
  });

  try {
    await testEnv.clearFirestore();
    await seedFirestore(testEnv);
    await runFirestoreTests(testEnv);
    await runStorageTests(testEnv);
    console.log("security-rules-ok");
  } finally {
    await testEnv.cleanup();
  }
}

async function seedFirestore(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users/alice"), {
      displayName: "Alice",
      handle: "alice_1",
      defaultSendMode: "confirm",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await setDoc(doc(db, "users/bob"), {
      displayName: "Bob",
      handle: "bob_1",
      defaultSendMode: "confirm",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await setDoc(doc(db, "users/alice/calendarEvents/eventA"), {
      ownerId: "alice",
      title: "Launch review",
      startAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
      endAt: new Date(Date.now() + 25 * 60 * 60 * 1000),
      timezone: "Asia/Seoul",
      source: "manual",
      details: "Agenda and room information",
      transcript: "",
      status: "active",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await setDoc(doc(db, "users/alice/friends/bob"), {
      uid: "bob",
      displayName: "Bob",
      handle: "bob_1",
      defaultSendMode: "confirm",
      addedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await setDoc(doc(db, "rooms/roomA"), {
      type: "direct",
      participantIds: ["alice", "bob"],
      title: "Alice, Bob",
      ownerId: "alice",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await setDoc(doc(db, "rooms/roomA/members/alice"), {
      uid: "alice",
      role: "owner",
      joinedAt: serverTimestamp(),
    });
    await setDoc(doc(db, "rooms/roomA/members/bob"), {
      uid: "bob",
      role: "member",
      joinedAt: serverTimestamp(),
    });
    await setDoc(doc(db, "rooms/roomA/messages/msg1"), {
      senderId: "alice",
      kind: "text",
      text: "hello",
      transcript: "",
      audioPath: null,
      durationMs: 0,
      sttStatus: "none",
      sendMode: "confirm",
      createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, "rooms/roomA/calendarProposals/proposalA"), {
      roomId: "roomA",
      messageId: "proposalMsgA",
      createdBy: "alice",
      title: "Dinner",
      details: "Pick a time",
      timezone: "Asia/Seoul",
      status: "open",
      candidates: [
        {
          candidateId: "candidate_1",
          startAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
          endAt: new Date(Date.now() + 25 * 60 * 60 * 1000),
        },
        {
          candidateId: "candidate_2",
          startAt: new Date(Date.now() + 26 * 60 * 60 * 1000),
          endAt: new Date(Date.now() + 27 * 60 * 60 * 1000),
        },
      ],
      votes: {
        bob: ["candidate_1"],
      },
      finalCandidateId: null,
      source: "manual",
      transcript: "",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await setDoc(doc(db, "rooms/roomA/calendarProposals/proposalA/votes/bob"), {
      uid: "bob",
      candidateIds: ["candidate_1"],
      updatedAt: serverTimestamp(),
    });
    await setDoc(doc(db, "transcriptionDrafts/draftA"), {
      ownerId: "alice",
      transcript: "hello",
      audioPath: "voice_drafts/alice/a.webm",
      createdAt: serverTimestamp(),
    });
  });
}

async function runFirestoreTests(testEnv) {
  const alice = testEnv.authenticatedContext("alice").firestore();
  const bob = testEnv.authenticatedContext("bob").firestore();
  const mallory = testEnv.authenticatedContext("mallory").firestore();
  const guest = testEnv.unauthenticatedContext().firestore();

  await assertSucceeds(getDoc(doc(alice, "users/bob")));
  await assertFails(getDoc(doc(guest, "users/alice")));
  await assertSucceeds(
    setDoc(doc(alice, "users/alice"), {
      displayName: "Alice",
      handle: "alice_1",
      defaultSendMode: "confirm",
      holidayCountryCode: "US",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    setDoc(doc(alice, "users/alice"), {
      displayName: "Alice",
      handle: "alice_1",
      defaultSendMode: "confirm",
      holidayCountryCode: "FR",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(getDoc(doc(alice, "users/alice/calendarEvents/eventA")));
  await assertFails(getDoc(doc(bob, "users/alice/calendarEvents/eventA")));
  await assertFails(getDoc(doc(guest, "users/alice/calendarEvents/eventA")));
  await assertFails(
    setDoc(doc(alice, "users/alice/calendarEvents/clientCreate"), {
      ownerId: "alice",
      title: "Client write blocked",
    }),
  );
  await assertFails(
    setDoc(
      doc(alice, "users/alice/calendarEvents/eventA"),
      { title: "Client update blocked" },
      { merge: true },
    ),
  );
  await assertFails(deleteDoc(doc(alice, "users/alice/calendarEvents/eventA")));
  await assertSucceeds(getDoc(doc(alice, "users/alice/friends/bob")));
  await assertFails(getDoc(doc(bob, "users/alice/friends/bob")));
  await assertFails(
    setDoc(doc(alice, "users/alice/friends/mallory"), {
      uid: "mallory",
      displayName: "Mallory",
      handle: "mallory_1",
    }),
  );

  await assertSucceeds(
    setDoc(doc(alice, "handles/alice_new"), {
      uid: "alice",
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    setDoc(doc(alice, "handles/bad!"), {
      uid: "alice",
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    setDoc(doc(alice, "handles/bob_taken"), {
      uid: "bob",
      updatedAt: serverTimestamp(),
    }),
  );

  await assertSucceeds(getDoc(doc(bob, "rooms/roomA/messages/msg1")));
  await assertFails(getDoc(doc(mallory, "rooms/roomA/messages/msg1")));
  await assertSucceeds(
    getDocs(
      query(
        collection(alice, "rooms"),
        where("participantIds", "array-contains", "alice"),
        orderBy("updatedAt", "desc"),
      ),
    ),
  );
  await assertFails(getDocs(collection(alice, "rooms")));
  await assertFails(
    getDocs(
      query(
        collection(mallory, "rooms"),
        where("participantIds", "array-contains", "alice"),
        orderBy("updatedAt", "desc"),
      ),
    ),
  );
  await assertSucceeds(
    setDoc(doc(alice, "rooms/roomA/messages/clientText"), {
      senderId: "alice",
      kind: "text",
      text: "client text is allowed",
      transcript: "",
      audioPath: null,
      durationMs: 0,
      sttStatus: "none",
      sendMode: "confirm",
      replyTo: null,
      deliveryStatus: "sent",
      clientCreated: true,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    setDoc(doc(alice, "rooms/roomA/messages/spoofedText"), {
      senderId: "bob",
      kind: "text",
      text: "spoofed text is blocked",
      transcript: "",
      audioPath: null,
      durationMs: 0,
      sttStatus: "none",
      sendMode: "confirm",
      replyTo: null,
      deliveryStatus: "sent",
      clientCreated: true,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    setDoc(doc(alice, "rooms/roomA/messages/clientPendingVoice"), {
      senderId: "alice",
      kind: "voice",
      text: "빠른 음성 메시지",
      transcript: "빠른 음성 메시지",
      audioPath: null,
      durationMs: 1000,
      sttStatus: "completed",
      sendMode: "instant",
      language: "ko-KR",
      replyTo: null,
      deliveryStatus: "sending",
      clientCreated: true,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(
    setDoc(
      doc(alice, "rooms/roomA/messages/clientPendingVoice"),
      {
        text: "client transcript update must use a callable function",
        transcript: "client transcript update must use a callable function",
        sttStatus: "completed",
        updatedAt: serverTimestamp(),
      },
      { merge: true },
    ),
  );
  await assertFails(
    setDoc(doc(alice, "rooms/roomA/messages/clientCompletedVoice"), {
      senderId: "alice",
      kind: "voice",
      text: "",
      transcript: "",
      audioPath: "voice_messages/roomA/clientVoice.m4a",
      durationMs: 1000,
      sttStatus: "processing",
      sendMode: "instant",
      replyTo: null,
      deliveryStatus: "sent",
      clientCreated: true,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    getDoc(doc(bob, "rooms/roomA/calendarProposals/proposalA")),
  );
  await assertSucceeds(
    getDoc(doc(alice, "rooms/roomA/calendarProposals/proposalA/votes/bob")),
  );
  await assertFails(
    getDoc(doc(mallory, "rooms/roomA/calendarProposals/proposalA")),
  );
  await assertFails(
    setDoc(doc(alice, "rooms/roomA/calendarProposals/clientProposal"), {
      title: "client writes are blocked",
    }),
  );
  await assertFails(
    setDoc(doc(bob, "rooms/roomA/calendarProposals/proposalA/votes/bob"), {
      candidateIds: ["candidate_2"],
    }),
  );

  await assertSucceeds(getDoc(doc(alice, "transcriptionDrafts/draftA")));
  await assertFails(getDoc(doc(bob, "transcriptionDrafts/draftA")));
  await assertFails(getDoc(doc(alice, "reports/reportA")));
}

async function runStorageTests(testEnv) {
  const alice = testEnv.authenticatedContext("alice").storage();
  const bob = testEnv.authenticatedContext("bob").storage();
  const mallory = testEnv.authenticatedContext("mallory").storage();
  const guest = testEnv.unauthenticatedContext().storage();

  await assertSucceeds(
    uploadString(ref(alice, "voice_drafts/alice/draft.webm"), "audio", "raw", {
      contentType: "audio/webm",
    }),
  );
  await assertFails(
    uploadString(ref(bob, "voice_drafts/alice/draft.webm"), "audio", "raw", {
      contentType: "audio/webm",
    }),
  );
  await assertFails(
    uploadString(
      ref(alice, "voice_drafts/alice/not-audio.txt"),
      "text",
      "raw",
      {
        contentType: "text/plain",
      },
    ),
  );

  await assertFails(
    uploadString(ref(alice, "voice_messages/roomA/msg.webm"), "audio", "raw", {
      contentType: "audio/webm",
      customMetadata: {
        roomId: "roomA",
        ownerId: "alice",
      },
    }),
  );
  await assertFails(
    uploadString(
      ref(mallory, "voice_messages/roomA/msg.webm"),
      "audio",
      "raw",
      {
        contentType: "audio/webm",
        customMetadata: {
          roomId: "roomA",
          ownerId: "mallory",
        },
      },
    ),
  );
  await assertFails(deleteObject(ref(alice, "voice_messages/roomA/msg.webm")));

  await assertSucceeds(
    uploadString(ref(alice, "attachments/roomA/alice/file.txt"), "hi", "raw", {
      contentType: "text/plain",
    }),
  );
  await assertFails(
    uploadString(ref(bob, "attachments/roomA/alice/file.txt"), "hi", "raw", {
      contentType: "text/plain",
    }),
  );
  await assertFails(
    getStorageDownloadUrl(guest, "attachments/roomA/alice/file.txt"),
  );
}

async function getStorageDownloadUrl(storage, storagePath) {
  return getDownloadURL(ref(storage, storagePath));
}
