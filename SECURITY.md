# Security

## Attack surface

This package computes over arrays of `Double`. It has no dependencies, opens no files,
makes no network calls, and parses no external formats — the only untrusted input it can
receive is numbers, from a caller that chose to hand them over.

The realistic failure mode is therefore a wrong answer, not a compromised process:
a detector that misses beats, or an estimator that reports a rate where there is none.
If your use of a physiological number has a safety consequence, treat it accordingly —
`respiratoryRate` returning `nil` means *unknown*, never *unchanged*.

This is not rated for a medical device and is not intended for diagnosis or treatment.

## Reporting

Report suspected vulnerabilities privately through GitHub's *Report a vulnerability*
button under the repository's Security tab, rather than in a public issue. Everything
else — a wrong result, a bad constant — belongs in an ordinary issue or preferably PR.

Note that this code has had no independent security review, and only the latest release
is looked at.
