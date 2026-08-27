/**
 * Coverage gate (NFR-MNT-001, enforced by NFR-MNT-004).
 *
 * Hardhat 3's built-in coverage writes an LCOV report but exposes no
 * fail-below-threshold flag, so the coverage requirement needs this script. Run it after
 * `hardhat test --coverage`; CI runs both and blocks merge on a non-zero exit.
 *
 * Scope is the project's own contracts — `contracts/`, excluding Solidity test sources —
 * which is the scope NFR-MNT-001 specifies ("excluding unmodified library dependencies").
 *
 * ## Branch coverage is currently UNMEASURABLE
 *
 * NFR-MNT-001 requires 100% of lines **and 100% of branches**. Hardhat 3.14.0 cannot
 * report branch coverage: its LCOV writer has the `BRDA`/`BRF`/`BRH` emission commented
 * out, annotated `currently EDR does not provide branch coverage information`
 * (`node_modules/hardhat/dist/src/internal/builtin-plugins/coverage/coverage-manager.js`).
 * The terminal report shows Line % and Statement %, never Branch %.
 *
 * This script therefore refuses to report a vacuous "branches 100% (0/0)" pass. When
 * branch records are absent it says so and fails, unless the gap is explicitly
 * acknowledged with COVERAGE_ALLOW_UNMEASURED_BRANCHES=1 — which CI sets, deliberately
 * and visibly, so the unresolved requirement is documented in the pipeline instead of
 * hidden by a green check. See docs/scaffold-notes.md.
 *
 * The honest caveat, repeated because a 100% number invites false confidence: coverage
 * measures execution, not assertion quality. With no fuzz or invariant tests in scope
 * (SRS Appendix C, AR-5), a fully covered suite can still miss arithmetic and
 * authorization edge cases. The binding bar is NFR-MNT-002 — every revert path asserted —
 * not this percentage.
 */
import { readFileSync } from "node:fs";

const LCOV_PATH = process.env.LCOV_PATH ?? "coverage/lcov.info";
const THRESHOLD = Number(process.env.COVERAGE_THRESHOLD ?? "100");
const ALLOW_UNMEASURED_BRANCHES = process.env.COVERAGE_ALLOW_UNMEASURED_BRANCHES === "1";

interface FileCoverage {
  file: string;
  linesFound: number;
  linesHit: number;
  branchesFound: number;
  branchesHit: number;
  hasBranchData: boolean;
}

function inScope(file: string): boolean {
  const normalized = file.replace(/\\/g, "/").replace(/^\.\//, "");
  return normalized.startsWith("contracts/") && !normalized.endsWith(".t.sol");
}

function parseLcov(contents: string): FileCoverage[] {
  const records: FileCoverage[] = [];
  let current: FileCoverage | undefined;

  for (const line of contents.split(/\r?\n/)) {
    if (line.startsWith("SF:")) {
      current = {
        file: line.slice(3).trim(),
        linesFound: 0,
        linesHit: 0,
        branchesFound: 0,
        branchesHit: 0,
        hasBranchData: false,
      };
      continue;
    }
    if (current === undefined) continue;

    if (line.startsWith("LF:")) current.linesFound = Number(line.slice(3));
    else if (line.startsWith("LH:")) current.linesHit = Number(line.slice(3));
    else if (line.startsWith("BRF:")) {
      current.branchesFound = Number(line.slice(4));
      current.hasBranchData = true;
    } else if (line.startsWith("BRH:")) {
      current.branchesHit = Number(line.slice(4));
      current.hasBranchData = true;
    } else if (line.startsWith("end_of_record")) {
      records.push(current);
      current = undefined;
    }
  }

  return records;
}

let contents: string;
try {
  contents = readFileSync(LCOV_PATH, "utf8");
} catch {
  console.error(`No coverage report at ${LCOV_PATH}. Run \`npx hardhat test --coverage\` first.`);
  process.exit(1);
}

const scoped = parseLcov(contents).filter((record) => inScope(record.file));

if (scoped.length === 0) {
  console.error(
    `No files under contracts/ appear in ${LCOV_PATH}. Either nothing was instrumented or the ` +
      `report scope changed — failing rather than reporting a vacuous 100%.`,
  );
  process.exit(1);
}

const pct = (hit: number, found: number) => (found === 0 ? 100 : (hit / found) * 100);
const fmt = (hit: number, found: number) => `${pct(hit, found).toFixed(2)}% (${hit}/${found})`;

const branchDataAvailable = scoped.some((record) => record.hasBranchData && record.branchesFound > 0);

let linesFound = 0;
let linesHit = 0;
let branchesFound = 0;
let branchesHit = 0;
const failures: string[] = [];

console.log(`Coverage gate: ${THRESHOLD}% of lines over contracts/ (excluding *.t.sol)`);
console.log(
  branchDataAvailable
    ? `               ${THRESHOLD}% of branches — branch data present in the report\n`
    : `               branches: NOT MEASURED — see the notice below\n`,
);

for (const record of scoped.sort((a, b) => a.file.localeCompare(b.file))) {
  linesFound += record.linesFound;
  linesHit += record.linesHit;
  branchesFound += record.branchesFound;
  branchesHit += record.branchesHit;

  const linePct = pct(record.linesHit, record.linesFound);
  const branchText = record.hasBranchData
    ? `branches ${fmt(record.branchesHit, record.branchesFound)}`
    : `branches unmeasured`;

  const ok =
    linePct >= THRESHOLD &&
    (!record.hasBranchData || pct(record.branchesHit, record.branchesFound) >= THRESHOLD);

  console.log(`  ${ok ? "PASS" : "FAIL"}  ${record.file}`);
  console.log(`        lines ${fmt(record.linesHit, record.linesFound)}   ${branchText}`);

  if (linePct < THRESHOLD) {
    failures.push(`${record.file}: lines ${linePct.toFixed(2)}% < ${THRESHOLD}%`);
  }
  if (record.hasBranchData) {
    const branchPct = pct(record.branchesHit, record.branchesFound);
    if (branchPct < THRESHOLD) {
      failures.push(`${record.file}: branches ${branchPct.toFixed(2)}% < ${THRESHOLD}%`);
    }
  }
}

console.log(`\nTotal: lines ${fmt(linesHit, linesFound)}`);
if (branchDataAvailable) {
  console.log(`       branches ${fmt(branchesHit, branchesFound)}`);
}

if (!branchDataAvailable) {
  const notice = [
    "",
    "=".repeat(78),
    "BRANCH COVERAGE IS NOT MEASURED — NFR-MNT-001 IS ONLY PARTLY VERIFIED",
    "=".repeat(78),
    "NFR-MNT-001 requires 100% of lines AND 100% of branches. This report contains no",
    "branch records, because Hardhat 3 does not emit them (its LCOV writer has the",
    "BRDA/BRF/BRH lines commented out: 'currently EDR does not provide branch coverage",
    "information'). The line figure above is real; the branch half of the requirement is",
    "unverified by tooling and rests on NFR-MNT-002 instead — every revert path in SRS",
    "3.1 having a test that asserts its specific failure.",
    "",
    "This is an open decision, recorded in docs/scaffold-notes.md. Resolve it by either",
    "amending NFR-MNT-001, or adding a tool that can measure branches.",
    "=".repeat(78),
  ].join("\n");

  if (ALLOW_UNMEASURED_BRANCHES) {
    console.warn(notice);
  } else {
    console.error(notice);
    console.error(
      "\nFailing because the gap is not acknowledged. Set COVERAGE_ALLOW_UNMEASURED_BRANCHES=1 to\n" +
        "proceed on the line gate alone (CI does this deliberately and visibly).",
    );
    process.exit(1);
  }
}

if (failures.length > 0) {
  console.error(`\nCoverage gate failed:`);
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

console.log("\nCoverage gate passed on every metric this toolchain can measure.");
