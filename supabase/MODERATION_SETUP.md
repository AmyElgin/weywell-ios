# Moderator queue setup

Weywell reports are not public when submitted. A trusted reviewer must approve
them before they can appear on the map. Moderator access is protected by Supabase
Auth and Row Level Security; the app contains no service-role credential.

## One-time project setup

1. Run `moderation_schema.sql` in Supabase Dashboard → SQL Editor.
2. In Authentication → Users, invite or create the reviewer account using a
   real email address and a strong password. Do not use anonymous sign-in for
   moderator accounts.
3. Copy that account's UUID from the Users page. In SQL Editor, add exactly that
   account:

   ```sql
   insert into public.moderators (user_id)
   values ('PASTE-THE-REVIEWER-USER-UUID-HERE');
   ```

4. In Weywell, open Profile → Moderator sign-in. Sign in with that account.
   Only a user whose UUID is in `public.moderators` can read the queue, view
   pending report photos, or change a pending report to approved/rejected.

To revoke moderator access, delete only that account's row from
`public.moderators` in the Supabase SQL Editor. The app keeps the moderator
session in memory only; signing out or closing Weywell clears it.

## Reviewing reports

The queue shows report category, public-place label, description, submission
time, and any optional photo. Approving exposes the report to the public map
until the server-set expiry (24 hours for road/safety reports; seven days for
neighbourhood break-in context). Rejecting keeps it off the map. The database
records the reviewer and review time. Push delivery, if configured, is triggered
only after approval.

Reviewers should reject reports that identify private individuals, include
private-home details, appear malicious or unverifiable, or contain imagery that
exposes faces, number plates, or sensitive locations. An alert is a community
report, not a police finding or a guarantee of safety.

## Current limitation

The app does not yet provide reporter appeals, user-to-user messaging, or a
formal second-review process. Keep moderator access limited to people you trust.
