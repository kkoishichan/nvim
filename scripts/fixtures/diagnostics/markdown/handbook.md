# Operations Handbook

Sample document with deliberate diagnostics (marksman + markdownlint-cli2).

Intended findings: MD013 line length, MD001 heading increment, MD022 headings not
surrounded by blank lines, MD024 duplicate heading, MD025 multiple top-level headings,
MD026 trailing punctuation in heading, MD033 inline HTML, MD034 bare URL, MD040 fenced
code without language, MD009 trailing spaces, MD010 hard tabs, MD012 multiple blank lines,
MD029 ordered list prefix, MD032 lists not surrounded by blank lines, MD047 missing final
newline, and unresolved links reported by marksman.

## Purpose

This handbook describes how the platform team deploys, monitors and recovers the services that make up the sample application, including the long operational notes that are easier to keep in one place than spread across several tickets.

The canonical copy lives at https://example.com/handbook and is mirrored here.

#### Scope

The document covers production and staging. Development environments are described in [the local guide](local-guide.md) and the shared [[architecture]] page.

## Environments
### Production
Production runs in two regions. Traffic is balanced by weighted DNS; the weights are adjusted during incidents as described below.

### Staging

Staging mirrors production at a tenth of the capacity. It is rebuilt every night from the production snapshot after secrets are scrubbed.

## Environments

The section title above is duplicated on purpose.

# Deployment!

Deployments go through the pipeline described in `scripts/deploy.sh`. The sequence is:

1. Build the artifact.
1. Upload it to the release bucket.
1. Stage the release on every node.
1. Run the smoke tests.
1. Switch the symlink and restart.
3. Prune old releases.

Before starting, confirm:
- the change was reviewed,
- the migration plan is attached,
- the on-call engineer is aware.
After the switch, watch the error rate for fifteen minutes.

```
deploy.sh --keep 5 artifact.tar.gz
```

```bash
deploy.sh --dry-run artifact.tar.gz
```

<details>
<summary>Manual fallback</summary>

If the pipeline is unavailable, the release can be staged by hand with `tar` and `rsync`.

</details>

## Monitoring

Dashboards are grouped by service. Each dashboard has the same four rows: traffic,
latency, errors and saturation. Alerts are routed as follows.

| Severity | Channel        | Response time |
| -------- | -------------- | ------------- |
| critical | pager          | 5 minutes     |
| high     | chat + pager   | 30 minutes    |
| medium   | chat           | next day      |
| low      | ticket         | next sprint   |

The following line has trailing spaces.   
	This line starts with a hard tab.

Latency targets are p50 under 120 ms and p99 under 800 ms for the API, and p50 under 40 ms for the edge cache; anything above those for more than ten minutes pages the on-call.



### Dashboards

* Traffic overview
* Error budget
- Capacity planning

### Log retention

Logs are retained for 30 days in hot storage and 400 days in cold storage. Requests for longer retention go through the data protection officer, see [retention policy](policies/retention.md#long-term).

## Incident response

1. Acknowledge the page within five minutes.
2. Open an incident channel named `inc-<date>-<short-title>`.
3. Assign roles: incident lead, communications, scribe.
4. Post updates every 30 minutes until resolved.
5. Schedule the review within three working days.

### Severity levels

| Level | Definition |
| ----- | ---------- |
| SEV1 | Customer-facing outage affecting most users |
| SEV2 | Degraded service or outage for a subset of users |
| SEV3 | Internal impact only |

### Communication templates

Initial update:

> We are investigating elevated error rates on the API. Next update in 30 minutes.

Resolution:

> The incident is resolved. A review will be published by <date>.

## Recovery

### Database

Point-in-time recovery is available for the last seven days. Restores take about
forty minutes per 100 GB. Test restores run every Sunday and the result is posted
to the operations channel. See [Backups](#backups) for the schedule.

### Cache

The cache can be flushed safely at any time; expect a latency spike of two to three
minutes while it warms.

### Queues

Dead-letter queues are inspected daily. Messages older than 48 hours are archived to
cold storage and summarised in the weekly report, see [queue runbook](runbooks/queues.md).

## Access

Access requests are filed in the ticket system. Production shell access requires a
second approver and expires after eight hours. Emergency access is granted through
the break-glass procedure and reviewed afterwards.

* Request access
* Wait for approval
* Use the bastion host
* Access is revoked automatically

## Appendix: checklists

### Pre-deployment

- [ ] Change reviewed
- [ ] Migration tested on staging
- [ ] Rollback plan written
- [ ] On-call informed

### Post-deployment

- [ ] Error rate stable
- [ ] Latency within targets
- [ ] Release notes published

### Quarterly

- [ ] Restore test performed
- [ ] Access review completed
- [ ] Runbooks updated

## Glossary

Artifact
: A build output ready for deployment.

Release
: A staged artifact with shared directories linked.

Switch
: The moment the `current` symlink points at a new release.

## Contacts

Platform team: platform@example.com. Escalation: see the on-call schedule at https://example.com/oncall.