import assert from "node:assert/strict";
import test from "node:test";

import { LiveLocationStore } from "../src/live-location-store.js";

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
