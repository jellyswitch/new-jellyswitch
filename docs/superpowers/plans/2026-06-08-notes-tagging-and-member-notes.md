# Notes: Tagging + Member-Scoped Notes Implementation Plan

> **⚠️ STATUS: IMPLEMENTED — DESIGN REVISED (2026-06-08).** All six items shipped.
> The original design below (a new `feed_items.subject_user_id` column + widening
> `User.taggable`) was **abandoned after discovering existing infrastructure**.
> What was actually built:
> - **#1** Web submit: removed Trix-incompatible disable gate + server empty-guard. (`9efe0818`)
> - **#2/#4** Tagging: a new **`User.mentionable`** scope (staff **+** approved members) and
>   **`GET /api/v1/admin/feed/mentionable_users`**; mobile now sources @mentions from it
>   instead of filtering page 1 of `/admin/members` to admin roles (the real "tagging
>   admins broken" cause). `notify_mentioned_users` regex replaced with name-matching.
>   `taggable` left **staff-only** (the profile dropdown uses it). (web `3672e2d0`, mobile `9f677bc`)
> - **#3** Mobile submit "does nothing": `keyboardShouldPersistTaps="handled"` on the feed
>   ScrollView (the keyboard ate the first tap). (mobile `9f677bc`)
> - **#5/#6** Member notes use the **existing `Note` model** (polymorphic `notable`, rich body,
>   auto-logs to the person timeline) via the existing `POST /admin/members/:id/add_note` —
>   **no new column**. Added a compose box on the member page's Notes tab (mobile `4c722e7`),
>   plus a **Chat tab** backed by new **`GET /admin/members/:id/conversations`** (member's
>   `MemberFeedback` threads + replies). (web `22891767`, mobile `d12ad63`)
> - Backend covered by tests (`User.mentionable` scope, mentionable_users endpoint,
>   conversations endpoint): 31 runs, 0 failures.
> - **Not done:** the *web* member detail page (`operator/users/show`) does not yet show
>   the notes/chat surface — mobile was the focus. Optional follow-up.
>
> The original task-by-task plan is kept below for historical context only.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make management notes fully usable — fix @tagging of admins, fix mobile note posting, let notes tag members too, and let staff create + view per-member notes (plus past chat) on a member's admin detail page.

**Architecture:** Notes stay `FeedItem` rows (`blob['type'] == 'post'`). A note *about a member* gets a new nullable `feed_items.subject_user_id` column so a member's detail page can query "notes about this member" cheaply (indexed), without a new model. Tagging is sourced from `User.taggable`, which we widen to include members. "Past chat" = the member's `MemberFeedback` threads, already in the DB.

**Tech Stack:** Rails 7 + Hotwire/Trix/Stimulus (web), React Native / Expo (mobile), Pundit, Postgres/jsonb.

**Repos:** `~/Downloads/new-jellyswitch` (Rails) and `~/Downloads/jellyswitch-mobile` (Expo). Ruby 3.3.10 via `export PATH="$HOME/.rbenv/versions/3.3.10/bin:$PATH"`. Mobile changes ship via `eas update` per brand (untethered / cowork-tahoe / choose-folsom).

**Already done (separate commit):** #1 — the web note submit button no longer stuck disabled (removed the Trix-incompatible `disable_button` gate; empty notes guarded server-side).

---

## File map

| File | Responsibility | Change |
|---|---|---|
| `app/controllers/operator/mentions_controller.rb` | @mention autocomplete source | filter by `?query=`, fix JSON |
| `app/views/operator/mentions/index.json.jbuilder` | JSON shape for the autocomplete | create/verify |
| `app/policies/mention_policy.rb` (or `user_policy`) | authorize the mentions list | verify it permits staff |
| `app/models/user.rb` (`taggable` scope) | who can be @mentioned | widen to include members |
| `db/migrate/*_add_subject_user_to_feed_items.rb` | per-member note link | create column + index |
| `app/models/feed_item.rb` | `belongs_to :subject_user` + `notes_about(user)` scope | add |
| `app/models/user.rb` | `has_many :notes_about_me` | add |
| `app/controllers/operator/feed_items_controller.rb` | accept `subject_user_id` on create | modify |
| `app/views/operator/users/show.html.erb` (member detail) | note compose + notes list + chat history | add sections |
| `app/controllers/api/v1/admin/feed_controller.rb` (`#create`, `notify_mentioned_users`) | mobile note create + mentions, accept subject_user_id | modify |
| `app/controllers/api/v1/admin/members_controller.rb` (member detail endpoint) | return member notes + feedback threads | modify |
| mobile `src/screens/admin/FeedScreen.js` / `MemberDetailScreen.js` | submit fix, member notes/chat UI | modify |

---

## Task 1: Reproduce + fix admin @tagging (web) — #2

**Files:**
- Modify: `app/controllers/operator/mentions_controller.rb`
- Verify/Create: `app/views/operator/mentions/index.json.jbuilder`
- Test: `test/controllers/operator/mentions_controller_test.rb`

- [ ] **Step 1: Write the failing request test**

```ruby
require "test_helper"
class Operator::MentionsControllerTest < ActionDispatch::IntegrationTest
  setup { @admin = users(:cowork_tahoe_admin); sign_in @admin }
  test "returns taggable staff as JSON for the autocomplete" do
    get mentions_path(format: :json, query: @admin.name.split.first)
    assert_response :success
    names = JSON.parse(response.body).map { |u| u["name"] || u["value"] }
    assert_includes names, @admin.name
  end
end
```

- [ ] **Step 2: Run it; observe the actual failure**

Run: `bin/rails test test/controllers/operator/mentions_controller_test.rb -v`
Expected: identifies the real break (empty JSON, missing jbuilder, Pundit denial, or no `?query` filtering). The `mentions_controller` currently returns `current_tenant.users.taggable` with **no `?query` filter** and relies on a JSON view — confirm `app/views/operator/mentions/index.json.jbuilder` exists and emits the shape the Stimulus `mentions_controller.js` + Tribute/library expects (typically `{ key: name, value: name }` or `{ name:, id: }`).

- [ ] **Step 3: Implement the fix in `mentions_controller#index`**

Filter server-side by `params[:query]` (case-insensitive name match) and cap the result:

```ruby
class Operator::MentionsController < Operator::BaseController
  def index
    @users = current_tenant.users.taggable
    @users = @users.where("name ILIKE ?", "%#{params[:query]}%") if params[:query].present?
    @users = @users.order(:name).limit(20)
    authorize @users
    respond_to do |format|
      format.html
      format.json
    end
  end
end
```

- [ ] **Step 4: Ensure the JSON view matches the front-end contract**

`app/views/operator/mentions/index.json.jbuilder`:

```ruby
json.array! @users do |user|
  json.id user.id
  json.name user.name
  json.value user.name
  json.key user.name
end
```

(Confirm the exact keys against `app/javascript/controllers/mentions_controller.js` — it calls `/mentions.json?query=` and feeds `users` to the editor library. Match whatever property the library reads for the label/insert value.)

- [ ] **Step 5: Run tests, then manually verify in the note form**

Run: `bin/rails test test/controllers/operator/mentions_controller_test.rb`
Expected: PASS. Then in the running app, open a note, type `@`, confirm staff names appear and insert.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/operator/mentions_controller.rb app/views/operator/mentions/index.json.jbuilder test/controllers/operator/mentions_controller_test.rb
git commit -m "fix(mentions): query-filter the @mention list and fix JSON shape"
```

---

## Task 2: Fix mobile note submit — #3

**Files:**
- Modify: mobile `src/screens/admin/FeedScreen.js` (`handlePostNote` + the @mention dropdown)
- Verify: `app/controllers/api/v1/admin/feed_controller.rb#create`

- [ ] **Step 1: Reproduce.** Build a debug Untethered build (`BRAND=untethered npx expo run:ios`), open admin FeedScreen → Notes → type a note → Post. Capture the exact failure (button disabled? request 4xx/5xx? `@mention` dropdown swallowing the submit?). `handlePostNote` already guards `!noteText.trim()` and calls `adminFeedAPI.create(noteText.trim())` → `POST /admin/feed { body }`. Likely culprits: (a) the mention dropdown’s keyboard/overlay intercepts the Post button tap, or (b) the create response shape changed and `setItems(prev => [response.data, ...])` throws after a successful post.

- [ ] **Step 2: Fix.** Based on the repro, the minimal fix is usually one of:
  - Dismiss the mention dropdown / keyboard before the Post button is hittable (wrap the compose in a `Pressable` that closes `mentionResults`, or move the Post button outside the dropdown’s touch area).
  - Make `handlePostNote` resilient: re-fetch the feed on success instead of optimistically prepending an assumed shape:

```js
const handlePostNote = async () => {
  if (!noteText.trim()) { Alert.alert('Empty Note', 'Please write something.'); return; }
  setSubmitting(true);
  try {
    await adminFeedAPI.create(noteText.trim());
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    setNoteText(''); setShowNote(false); setMentionResults([]);
    await fetchFeed(true); // reload so the new note shows with the server shape
  } catch (e) {
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
    Alert.alert('Error', e?.response?.data?.error || 'Could not post note. Please try again.');
  } finally { setSubmitting(false); }
};
```

- [ ] **Step 3: Verify on the sim** the note posts and appears. **Step 4: Commit** in the mobile repo.

---

## Task 3: Allow tagging members, not just admins — #4

**Files:**
- Modify: `app/models/user.rb` (`taggable` scope)
- Modify: `app/controllers/api/v1/admin/feed_controller.rb#notify_mentioned_users`
- Test: `test/models/user_test.rb`

- [ ] **Step 1: Failing test for the widened scope**

```ruby
test "taggable includes approved members, not just staff" do
  op = operators(:cowork_tahoe)
  member = users(:cowork_tahoe_member) # approved, role member/unassigned
  assert_includes op.users.taggable, users(:cowork_tahoe_admin)
  assert_includes op.users.taggable, member
end
```

- [ ] **Step 2: Run — fails** (member excluded).

- [ ] **Step 3: Widen the scope** in `app/models/user.rb`. Keep staff, add approved, non-archived members; exclude pending/archived:

```ruby
scope :taggable, -> {
  admins.or(general_managers).or(community_managers)
    .or(where(approved: true, archived: false))
    .distinct
}
```

(Adjust to the real column names; confirm `approved`/`archived` exist on User.)

- [ ] **Step 4: Run — passes.** Mentions autocomplete (Task 1) now surfaces members automatically (same `User.taggable` source).

- [ ] **Step 5: Mobile mentions.** `notify_mentioned_users` (api/v1/admin/feed_controller.rb:314) resolves `@First Last` by a brittle name regex over `operator.users`. Tighten it to resolve against `operator.users.taggable` and match full name first, then fall back, to avoid mis-tagging. Commit.

---

## Task 4: Per-member notes — data model + create from member page — #5

**Files:**
- Create: `db/migrate/<ts>_add_subject_user_to_feed_items.rb`
- Modify: `app/models/feed_item.rb`, `app/models/user.rb`
- Modify: `app/controllers/operator/feed_items_controller.rb` (+ params)
- Modify: `app/views/operator/users/show.html.erb` (note compose scoped to the member)
- Test: `test/models/feed_item_test.rb`, `test/system/member_notes_test.rb`

- [ ] **Step 1: Migration** — add the nullable, indexed subject link:

```ruby
class AddSubjectUserToFeedItems < ActiveRecord::Migration[7.2]
  def change
    add_reference :feed_items, :subject_user, null: true, index: true
  end
end
```

Run: `bin/rails db:migrate`.

- [ ] **Step 2: Model wiring**

`feed_item.rb`:
```ruby
belongs_to :subject_user, class_name: "User", optional: true
scope :notes, -> { where("blob->>'type' = ?", "post") }
scope :about, ->(user) { where(subject_user_id: user.id) }
```
`user.rb`:
```ruby
has_many :notes_about_me, -> { where("blob->>'type' = ?", "post") },
         class_name: "FeedItem", foreign_key: :subject_user_id
```

- [ ] **Step 3: Accept `subject_user_id` on create** in `operator/feed_items_controller.rb#create` — permit it and pass it into `FeedItems::Create` (add `subject_user` to `FeedItems::Save`’s delegated context and `@feed_item.subject_user_id = subject_user_id`). A member-scoped note is still a normal feed post; `subject_user_id` just records who it’s about. Failing model test → implement → pass.

- [ ] **Step 4: Member detail compose (web).** In `app/views/operator/users/show.html.erb`, add a "Notes" card that renders the same `operator/feed_items/_form` partial with a hidden `subject_user_id = @user.id`, posting to `new_feed_item_path`. Reuse the (now-working) note form. System test (`test/system/member_notes_test.rb`): visit the member page, post a note (drive Trix via `editor.insertString`), assert it appears in the member’s notes list.

- [ ] **Step 5: Commit** after each green step.

---

## Task 5: Member account page shows notes + past chat — #6

**Files:**
- Modify: `app/views/operator/users/show.html.erb` (notes list + chat history)
- Modify: `app/controllers/api/v1/admin/members_controller.rb` (member detail JSON) + mobile `MemberDetailScreen.js`
- Test: `test/system/member_notes_test.rb`, `test/controllers/api/v1/admin/members_controller_test.rb`

- [ ] **Step 1: Web — notes list.** Under the member’s Notes card, render `@user.notes_about_me.order(created_at: :desc)` (each note’s rich text + author + timestamp).

- [ ] **Step 2: Web — past chat.** Render the member’s `MemberFeedback` threads (the existing chat/feedback model) for this member, newest first, each linking to the full thread (`member_feedback_path`). These are the "past chat conversations."

- [ ] **Step 3: Mobile parity.** Extend the admin member-detail endpoint (`api/v1/admin/members_controller#show`) to include `notes: FeedItem.about(member).notes...` and `feedback_threads: member.member_feedbacks...`. In `MemberDetailScreen.js`, add a "Notes" section (with a compose that posts `POST /admin/feed { body, subject_user_id }`) and a "Conversations" section listing the feedback threads (tap → MessageDetail). The mobile `adminFeedAPI.create` gains an optional `subjectUserId` → body.

- [ ] **Step 4: Tests** — request test asserts the member-detail JSON includes notes + feedback threads; system test asserts the web member page shows a posted note and an existing feedback thread. Green → **commit**.

---

## Ship
- Web/backend: merge to `main`, `git push origin main`, `git push heroku main` (release phase runs the migration).
- Mobile: `BRAND=<brand> npx eas update --branch production` for untethered, cowork-tahoe, choose-folsom.

## Self-review notes
- Every requirement #2–#6 maps to a task (1,2,3,4,5 respectively; #4 spans Task 3).
- Design decision locked: reuse `FeedItem` + `subject_user_id` (not a new model) — least new surface, indexed lookups, and the member-detail "notes" and feed "notes" stay one concept.
- Open item to confirm during Task 1: the exact JSON property the web mentions library reads (`value` vs `key` vs `name`) — verify against `mentions_controller.js`.
- Open item to confirm during Task 2: the real mobile-submit failure (button vs request vs response-shape) — the plan fixes the two most likely causes.
