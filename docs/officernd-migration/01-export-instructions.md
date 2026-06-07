# OfficeRnD → Jellyswitch: Export Instructions (for the operator)

Send this to the coworking-space contact (e.g. Denise) so the OfficeRnD data dump
comes back in a usable shape the first time.

> **Why some things aren't on this list:** the space's existing Stripe account gets
> *connected* to Jellyswitch during onboarding. Once connected, Jellyswitch reads
> **customers, cards-on-file, and historical invoices directly from Stripe**
> (`Onboarding::FetchStripeCustomers`). So the CSV's main job is to supply what
> Stripe does **not** know about — team groupings, who's on which plan, and
> prepaid **credit balances** (an internal Jellyswitch ledger, `User.credit_balance`).

---

## Forwardable message

**Subject: OfficeRnD data export — what we need for the Jellyswitch migration**

Hi Denise,

To bring your members and their history into the new app cleanly, could you export
the following from OfficeRnD? CSV or Excel, **one file per item**, and please **keep
all ID columns** — especially anything labeled "Stripe" — because those are the keys
we use to line everything up automatically.

**1. Members (people)** — one row per person
- Name, email, phone, status (active/inactive), start date, home/primary location
- Company/team they belong to (if any)
- **Stripe Customer ID** (OfficeRnD stores this on each member — most important column)

**2. Companies / Teams** — if any teams are billed as a unit
- Company name, billing contact (name + email), list of members
- **Stripe Customer ID** for the company, if it bills as one

**3. Memberships / Plans** — who's on what
- Member or company, plan name, price, billing interval (monthly/etc.), start date,
  active vs. cancelled
- **Stripe Subscription ID** and **Stripe Plan/Price ID** if shown

**4. Invoices / billing history** — the records you want carried over
- Invoice number, date, due date, amount, amount paid, status
  (paid/open/refunded/void), description or line items, and which member/company
- **Stripe Invoice ID** and **Stripe Payment/Charge ID** for each (critical — these
  anchor each invoice to the real Stripe record)

**5. Prepaid balances & passes** — *only exists in OfficeRnD, not Stripe:*
- Remaining **meeting-room / hour credits** or package balances per member
- Unredeemed **day passes** already paid for
- Day-pass history if you want it shown (date, type, price, paid vs. complimentary)

Separately from the files:
- The **Stripe account ID** (`acct_…`) of the account OfficeRnD bills through.
- During onboarding we'll send a **"Connect with Stripe" authorization link** — approving
  it lets the app read that account directly so cards and invoices come across without
  anyone re-entering anything.

Two quick questions so we map it right:
- Do you bill any **teams/companies as a single account**, or is everyone individual?
- Are there members on **manual/offline payment** (not charged through Stripe)?

Thanks!

---

## The join keys that make the automatic mapping work

| Entity   | Primary key for matching        | Fallback        |
|----------|---------------------------------|-----------------|
| Member   | Stripe Customer ID              | email (lowercased) |
| Company  | Stripe Customer ID              | company name    |
| Invoice  | Stripe Invoice ID               | invoice number + customer |
| Plan     | Stripe Plan/Price ID            | plan name (mapped by hand in the wizard) |

If the Stripe IDs are present, the import is deterministic. If they're missing we fall
back to email/name matching and surface an **exceptions list** for manual resolution.
