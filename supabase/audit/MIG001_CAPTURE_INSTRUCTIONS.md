# MIG-001 — How to Run the Live Schema Capture

This is a manual step. Claude Code does not and must not connect to Supabase directly — you run the query yourself, in your own browser session, using your own credentials, which never leave your machine or get pasted into this conversation.

## Steps

1. Open the correct live PERSPECTIVES Supabase project in your browser (app.supabase.com), using your own login.
2. Open the **SQL Editor**.
3. Create a **new, untitled query**.
4. Open [`MIG001_READ_ONLY_SCHEMA_CAPTURE.sql`](MIG001_READ_ONLY_SCHEMA_CAPTURE.sql) in this same folder and paste its **complete contents** into the query editor.
5. Before running it, visually confirm the query contains no mutating statement — it should be a single block of `WITH ... SELECT ...` and nothing else. There is no `INSERT`, `UPDATE`, `DELETE`, `ALTER`, `DROP`, `CREATE`, `GRANT`, or `REVOKE` anywhere in it.
6. Run it **once**. It returns exactly one row with one column, `mig001_schema_capture`, containing a JSON object.
7. Download that single result as **CSV** or **JSON** using the SQL Editor's export/download option.
8. Save the downloaded file locally at exactly:

   ```
   /Users/mazenkafienah/Desktop/Apps Admin/Perspectives/MIG-001_LOCAL_CAPTURE/live_schema_capture.json
   ```

   or, if you downloaded CSV instead:

   ```
   /Users/mazenkafienah/Desktop/Apps Admin/Perspectives/MIG-001_LOCAL_CAPTURE/live_schema_capture.csv
   ```

   This folder sits outside every Git repository in the workspace and is not tracked by Git. Create it if it does not already exist.

9. **Never** paste a database password, service-role key, access token, anon key, or connection string into this conversation. This capture file itself contains none of those — it is schema metadata only — but the instruction stands regardless.
10. Come back to this Claude Code conversation and say only that the capture file has been saved. You do not need to paste its contents.

## What happens next

Once you confirm the file exists, Claude Code will read it from disk, verify it, and use it to reconcile the live schema against the planning documents — all without ever having connected to Supabase itself.
