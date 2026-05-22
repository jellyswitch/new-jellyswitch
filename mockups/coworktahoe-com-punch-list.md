# Cowork Tahoe website — fix punch list

Things found on **coworktahoe.com** while building the redesigned mockup. Most are stale content, SEO problems, or inconsistencies with untethered.space that need resolution before / after the thin-site rewrite.

---

## 🔴 Critical — fix before launch of redesign

### 1. Day-pass price mismatch ($35 vs $40)
- **coworktahoe.com homepage** currently advertises `Book a $35 Day Pass here!`
- **untethered.space/cowork-tahoe-south-lake-tahoe-ca/** lists day pass at **$40**
- **Action**: pick one and align both sites. Mismatched prices are an SEO trust issue and confuse customers who comparison-shop. Recommend $40 (matches the rest of the network).

### 2. Private office count + pricing inconsistency
- **coworktahoe.com/private-offices**: "30 private offices ranging in size from 90 square feet to 230 square feet... starting at $500.00 per month"
- **untethered.space/cowork-tahoe-south-lake-tahoe-ca/**: 24 offices, $600+/month
- **Yelp listing (April 2026)**: 24 offices
- **Action**: confirm real count (likely 24) and real price (likely $600+). Update coworktahoe.com page or take it offline if redesign will replace it.

### 3. Membership-options page returns 404
- `coworktahoe.com/membership-options/` → **HTTP 404 Not Found**
- Tested 2026-05-19 during research
- **Action**: either restore the page, redirect it to the new comparison section, or take all links to it off the site so it doesn't appear in nav/footer.

### 4. Membership login portal status unknown
- Homepage links to "member login" but the destination wasn't verified to work
- **Action**: confirm whether login still functions or routes to Untethered app — fix the link accordingly.

---

## 🟡 SEO problems — fix during redesign

### 5. Revolution Slider photos are invisible to crawlers
- Homepage uses the Revolution Slider WordPress plugin, which lazy-loads images via JavaScript
- Source HTML shows only `dummy.png` placeholders; real photos never appear in HTML for Google or Bing to index
- **Result**: zero image SEO from the homepage despite having a real photo shoot done in 2024
- **Action**: in the redesign, use plain `<img>` tags with proper `alt` attributes. Drop Revolution Slider entirely. Static images are faster, more accessible, and indexable.

### 6. No real photography accessible from homepage HTML
- The only actual images served are `cowork-tahoe-logo.jpg` and `logo.png`
- All interior shots are hidden behind the slider plugin
- **Action**: rewrite homepage with static `<img>` tags pulling from the 2024 photo shoot (Cowork2024-*.jpg files already hosted at `untethered.space/wp-content/uploads/2024/11/`). Consider mirroring to `coworktahoe.com/wp-content/uploads/` for self-hosted SEO benefit.

### 7. About-us page is almost empty
- Only contains the logo + `tangles-cropped.jpg` (one image)
- No team photos, no story content rendered statically, no local-context SEO
- **Action**: rewrite about page with: founding story (2016), team intro, Untethered acquisition framing, location-specific paragraphs (Regan Beach proximity, midtown character).

### 8. No conference room photos anywhere
- Neither coworktahoe.com nor untethered.space has visible photography of the boardrooms / meeting rooms
- This is one of four core products being marketed
- **Action**: shoot 4–6 photos of the conference rooms next time a photographer is on site. At minimum: wide shot of each board room, detail of the A/V setup, an in-use shot with people.

### 9. Logo file naming + duplication
- Two logo files exist: `cowork-tahoe-logo-e1542317179731.jpg` (2018) and `logo.png` (no date in filename)
- Plus a third on untethered.space: `cowork-tahoe-transparent-150x150.png` (2025)
- **Action**: pick one canonical CT logo and use it everywhere. Delete the others. The 2025 transparent version is the post-acquisition styling — use that.

---

## 🟢 Nice-to-have — schedule when bandwidth allows

### 10. Phone number prominence
- Phone is `530-600-3447` per the private-offices page
- Not visible on homepage
- **Action**: surface phone in nav or hero on the redesigned page (locals call before they web-book)

### 11. Hours communication is buried
- Hours (M–F 9–5) appear on private-offices page footer but not on homepage
- **Action**: standard practice — put hours in the footer of every page, plus on the practical-info section of the new landing.

### 12. Blog posts inventory
- Homepage references a blog but the blog content wasn't audited
- **Action**: list all blog posts. Decide which to keep (evergreen local content = SEO asset), which to retire (stale operational announcements), which to 301-redirect to relevant Untethered.space content. Don't just delete — old URLs have backlinks.

### 13. Reciprocal access for Untethered members not advertised
- A real perk: CT members get access at Zephyr Cove + future Untethered locations
- Currently invisible on coworktahoe.com
- **Action**: include in the redesigned site (already in the mockup) — strengthens the "why join CT vs The Forest" pitch.

### 14. Google Business Profile review prompts
- 4.9 stars from 16 reviews — strong but **only 16**. For a 9-year-old business in a market this small, more reviews are reachable.
- **Action**: build a post-tour and post-month-1 review-request flow. The mobile app could trigger this automatically (Jellyswitch project).

### 15. Schema.org structured data missing
- Page source contains no JSON-LD or microdata for `LocalBusiness`
- **Action**: add `LocalBusiness` + `WorkLocation` schema to the redesigned page (address, hours, phone, price range, accepted payments). Easy SEO win.

### 16. Outdated copyright + footer year
- Footer year not verified — common WordPress trap. Confirm it's dynamic (`<?php echo date('Y'); ?>`) not hard-coded.

---

## Summary

| Priority | Count | What |
|---|---|---|
| 🔴 Critical | 4 | Pricing mismatches, broken page, login |
| 🟡 SEO problems | 5 | Crawler-invisible images, thin content |
| 🟢 Nice-to-have | 7 | Polish, schema, review pipeline |

**Recommended sequencing:**
1. **Today**: fix the day-pass price (5 minutes, biggest customer-trust risk).
2. **This week**: take down or redirect the 404 membership-options page; reconcile private-office count + pricing.
3. **During redesign**: rewrite homepage without Revolution Slider, add static `<img>` tags, write proper about-us page.
4. **Next photographer visit**: capture conference rooms.
5. **Ongoing**: review-request flow via Jellyswitch mobile app.
