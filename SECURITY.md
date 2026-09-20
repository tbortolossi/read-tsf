# Security policy

## Reporting a vulnerability

Open a [security advisory](https://github.com/tbortolossi/read-tsf/security/advisories/new)
on this repository, or email thomasbortolossi@gmail.com. Expect an
acknowledgement within a week.

This repository ships documentation, not executable code that touches a
firewall. The realistic issues are a wrong instruction that leads someone to
a damaging command, and data that should never have been committed.

## Do not attach a tech support file

A TSF contains the full configuration of a production firewall: hostnames,
serials, addresses, users, certificates and policy. **Never attach one, or
an extract of one, to an issue, a pull request or an advisory** — including
one you believe is anonymized.

To share a real archive for a discussion, anonymize it first with
[tsf-anonymizer](https://github.com/tbortolossi/tsf-anonymizer), keep the
`*.mapping.json` sidecar to yourself, and even then prefer quoting the few
lines that matter over attaching the archive.

If customer data reaches this repository, report it the same way as a
vulnerability. Git history is permanent, so the fix is a history rewrite and
the sooner it starts the better.
