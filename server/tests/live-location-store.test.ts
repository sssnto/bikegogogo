import assert from "node:assert/strict";
import test from "node:test";

import {
  LiveLocationStore,
  MeetingPointStore
} from "../src/live-location-store.js";

test("live locations expire after the configured retention window", () => {
  let now = new Date("2026-07-28T00:00:00.000Z");
  const store = new LiveLocationStore(90_000, () => now);

  store.upsert("grp_test", "usr_alpha", {
    latitude: 39.9042,
    longitude: 116.4074,
    capturedAt: now.toISOString()
  });
  assert.equal(store.list("grp_test").length, 1);

  now = new Date(now.getTime() + 89_999);
  assert.equal(store.list("grp_test").length, 1);

  now = new Date(now.getTime() + 2);
  assert.equal(store.list("grp_test").length, 0);
});

test("removing a group clears every member location", () => {
  const store = new LiveLocationStore();
  const capturedAt = new Date().toISOString();
  store.upsert("grp_test", "usr_alpha", {
    latitude: 39.9042,
    longitude: 116.4074,
    capturedAt
  });
  store.upsert("grp_test", "usr_bravo", {
    latitude: 39.905,
    longitude: 116.408,
    capturedAt
  });

  store.removeGroup("grp_test");

  assert.deepEqual(store.list("grp_test"), []);
});

test("removing a user clears their locations across groups", () => {
  const store = new LiveLocationStore();
  const capturedAt = new Date().toISOString();
  store.upsert("grp_first", "usr_alpha", {
    latitude: 39.9042,
    longitude: 116.4074,
    capturedAt
  });
  store.upsert("grp_second", "usr_alpha", {
    latitude: 39.905,
    longitude: 116.408,
    capturedAt
  });
  store.upsert("grp_second", "usr_bravo", {
    latitude: 39.906,
    longitude: 116.409,
    capturedAt
  });

  store.removeUser("usr_alpha");

  assert.deepEqual(store.list("grp_first"), []);
  assert.deepEqual(
    store.list("grp_second").map((location) => location.userId),
    ["usr_bravo"]
  );
});

test("meeting points expire and can be removed with their owner", () => {
  let now = new Date("2026-07-28T00:00:00.000Z");
  const store = new MeetingPointStore(
    6 * 60 * 60 * 1000,
    () => now
  );

  const meetingPoint = store.set("grp_first", "usr_alpha", {
    latitude: 39.9042,
    longitude: 116.4074,
    title: "东门",
    horizontalAccuracyMeters: 8,
    capturedAt: now.toISOString()
  });
  assert.equal(meetingPoint.expiresAt, "2026-07-28T06:00:00.000Z");
  assert.equal(store.get("grp_first")?.title, "东门");

  now = new Date("2026-07-28T05:59:59.000Z");
  assert.equal(store.get("grp_first")?.setByUserId, "usr_alpha");

  now = new Date("2026-07-28T06:00:00.000Z");
  assert.equal(store.get("grp_first"), undefined);

  now = new Date("2026-07-28T07:00:00.000Z");
  store.set("grp_second", "usr_alpha", {
    latitude: 31.2304,
    longitude: 121.4737,
    title: "咖啡店",
    capturedAt: now.toISOString()
  });
  store.removeUser("usr_alpha");
  assert.equal(store.get("grp_second"), undefined);
});
