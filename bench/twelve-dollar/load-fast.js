/**
 * The load test. One virtual user (VU) = one person browsing the feed, with think time.
 * A submission's score is the highest VUS that passes a 5-minute hold (see README.md).
 *
 *   k6 run -e VUS=2000 bench/load.js
 *   k6 run -e BASE_URL=http://10.0.0.5 -e VUS=8000 bench/load.js
 *
 * Env: BASE_URL (default http://127.0.0.1:3000), VUS (default 100), DURATION (default 5m),
 *      RAMP_UP (default 60s), TOKENS (default seed/tokens.json).
 *
 * User loop: GET /feed -> think 3-7 s -> GET /posts/:id (one from the feed) -> think 3-8 s
 *   -> like it (15% chance) -> write a post (2% chance) -> idle 5-15 s -> repeat.
 *
 * Pass: p95 < 500 ms, p99 < 1000 ms, under 1% failed requests (k6 exits non-zero on a fail).
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import { SharedArray } from 'k6/data';

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:3000';
const VUS = Number(__ENV.VUS || 100);
const SCALE = Number(__ENV.SCALE || 1);
const LIKE_PROB = Number(__ENV.LIKE_PROB ?? 0.15);
const POST_PROB = Number(__ENV.POST_PROB ?? 0.02);
const tokens = new SharedArray('tokens', () => JSON.parse(open(__ENV.TOKENS || '../seed/tokens.json')));

export const options = {
  scenarios: {
    users: {
      executor: 'ramping-vus',
      stages: [
        { duration: __ENV.RAMP_UP || '60s', target: VUS },
        { duration: __ENV.DURATION || '5m', target: VUS },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.01'],
  },
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

const between = (lo, hi) => lo + Math.random() * (hi - lo);

export default function () {
  const user = tokens[(__VU - 1) % tokens.length];
  const auth = { headers: { Authorization: `Bearer ${user.token}`, 'Content-Type': 'application/json' } };
  if (__ITER === 0) sleep(between(0, 5) / SCALE); // spread out VUs that start in the same tick

  const feed = http.get(`${BASE_URL}/feed`, { tags: { name: 'GET /feed' } });
  if (!check(feed, { 'feed 200': (r) => r.status === 200 })) { sleep(between(3, 7) / SCALE); return; }
  const posts = feed.json('posts');
  const post = posts[Math.floor(Math.random() * posts.length)];
  sleep(between(3, 7) / SCALE);

  check(http.get(`${BASE_URL}/posts/${post.id}`, { tags: { name: 'GET /posts/:id' } }), { 'post 200': (r) => r.status === 200 });
  sleep(between(3, 8) / SCALE);

  if (Math.random() < LIKE_PROB) {
    const r = http.post(`${BASE_URL}/posts/${post.id}/like`, null, { ...auth, tags: { name: 'POST /posts/:id/like' } });
    check(r, { 'like 200/201': (r) => r.status === 200 || r.status === 201 });
  }
  if (Math.random() < POST_PROB) {
    const body = JSON.stringify({ body: `${user.username} says hi at ${new Date().toISOString()} (VU ${__VU}, iter ${__ITER})` });
    check(http.post(`${BASE_URL}/posts`, body, { ...auth, tags: { name: 'POST /posts' } }), { 'create 201': (r) => r.status === 201 });
  }
  sleep(between(5, 15) / SCALE);
}
