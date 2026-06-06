import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, "..");

function usage() {
  console.error("Usage: node build_agent_regression_tracker.mjs <run-json> <output-xlsx>");
}

function issueLabel(issues) {
  return issues.length ? issues.join(", ") : "none";
}

function normalizeStatus(status) {
  if (status === "completed") return "Completed";
  if (status === "failed") return "Failed";
  if (status === "running") return "Timed out / still running";
  return status;
}

function normalizeVerdict(verdict) {
  if (verdict === "pass") return "Pass";
  if (verdict === "warn") return "Warn";
  if (verdict === "fail") return "Fail";
  return verdict;
}

function collectCounts(results) {
  const counts = { pass: 0, warn: 0, fail: 0 };
  for (const result of results) {
    counts[result.verdict] = (counts[result.verdict] ?? 0) + 1;
  }
  return counts;
}

function pickObservations(results) {
  const byId = Object.fromEntries(results.map((result) => [result.case_id, result]));
  return [
    [
      "Upload ingest still fails after extract and initial writes",
      byId["6"]?.summary ?? "",
      "High",
    ],
    [
      "Lint does not stop at reporting and continues into broad auto-fix flow",
      byId["8"]?.summary || "Task stayed running past timeout window.",
      "High",
    ],
    [
      "Record text intent is successful but currently creates a heavyweight wiki entity page",
      byId["5"]?.summary ?? "",
      "Medium",
    ],
  ];
}

export async function buildTracker(runJsonPathArg, outputPathArg) {
  const runJsonPath = path.resolve(rootDir, runJsonPathArg);
  const outputPath = path.resolve(rootDir, outputPathArg);
  const raw = await fs.readFile(runJsonPath, "utf8");
  const run = JSON.parse(raw);
  const results = [...run.results].sort((a, b) => Number(a.case_id) - Number(b.case_id));
  const counts = collectCounts(results);

  const workbook = Workbook.create();
  const summary = workbook.worksheets.add("Summary");
  const cases = workbook.worksheets.add("Cases");

  summary.mergeCells("A1:H1");
  summary.getRange("A1").values = [["Piki Agent Regression Tracker"]];
  summary.getRange("A1:H1").format = {
    fill: "#1F4E78",
    font: { bold: true, size: 18, color: "#FFFFFF" },
    horizontalAlignment: "center",
    verticalAlignment: "center",
    rowHeightPx: 28,
  };

  const metaRows = [
    ["Run file", path.relative(rootDir, runJsonPath)],
    ["Run date", run.run_date],
    ["Service URL", run.service_url],
    ["Provider", run.provider],
    ["Model", run.model],
    ["Source vault", run.source_vault],
    ["Temp vault strategy", run.temp_vault_strategy],
  ];
  summary.getRange("A3:B9").values = metaRows;
  summary.getRange("A3:A9").format = {
    font: { bold: true, color: "#1F1F1F" },
    fill: "#D9EAF7",
  };
  summary.getRange("B3:B9").format = {
    fill: "#F8FBFE",
  };

  const total = results.length;
  const completed = results.filter((result) => result.task_status === "completed").length;
  const failed = results.filter((result) => result.task_status === "failed").length;
  const timedOut = results.filter((result) => result.timed_out).length;

  const kpiLabels = ["Total cases", "Completed", "Failed", "Timed out", "Pass", "Warn", "Fail verdicts"];
  const kpiValues = [total, completed, failed, timedOut, counts.pass, counts.warn, counts.fail];
  const kpiColors = ["#D9EAF7", "#DDF3E4", "#FCE4E4", "#FDF2CC", "#DDF3E4", "#FFF2CC", "#FCE4E4"];

  for (let i = 0; i < kpiLabels.length; i += 1) {
    const col = String.fromCharCode("D".charCodeAt(0) + i);
    summary.getRange(`${col}3`).values = [[kpiLabels[i]]];
    summary.getRange(`${col}4`).values = [[kpiValues[i]]];
    summary.getRange(`${col}3`).format = {
      font: { bold: true, color: "#1F1F1F" },
      fill: kpiColors[i],
      horizontalAlignment: "center",
    };
    summary.getRange(`${col}4`).format = {
      font: { bold: true, size: 16, color: "#1F1F1F" },
      fill: "#FFFFFF",
      horizontalAlignment: "center",
    };
  }

  summary.getRange("A12:G12").values = [[
    "Case ID",
    "Intent",
    "Task status",
    "Verdict",
    "Key issues",
    "Affected files",
    "Task ID",
  ]];
  summary.getRange("A13:G20").values = results.map((result) => [
    result.case_id,
    result.intent,
    normalizeStatus(result.task_status),
    normalizeVerdict(result.verdict),
    issueLabel(result.issues),
    result.affected_files.length,
    result.task_id,
  ]);
  summary.getRange("A12:G12").format = {
    font: { bold: true, color: "#FFFFFF" },
    fill: "#2F75B5",
  };

  summary.getRange("A23:C23").values = [["Key observation", "Evidence", "Priority"]];
  summary.getRange("A24:C26").values = pickObservations(results);
  summary.getRange("A23:C23").format = {
    font: { bold: true, color: "#FFFFFF" },
    fill: "#7A3E00",
  };

  cases.getRange("A1:L1").values = [[
    "Case ID",
    "Intent",
    "Prompt",
    "Task status",
    "Verdict",
    "Timed out",
    "Issues",
    "Affected files",
    "Summary",
    "Answer excerpt",
    "Tool summary excerpt",
    "Task ID",
  ]];

  cases.getRange("A2:L9").values = results.map((result) => [
    Number(result.case_id),
    result.intent,
    result.prompt,
    normalizeStatus(result.task_status),
    normalizeVerdict(result.verdict),
    result.timed_out ? "Yes" : "No",
    issueLabel(result.issues),
    result.affected_files.join("\n"),
    result.summary,
    (result.answer || "").slice(0, 500),
    (result.event_summary.tool_summaries || []).join(" | ").slice(0, 800),
    result.task_id,
  ]);

  cases.getRange("A1:L1").format = {
    font: { bold: true, color: "#FFFFFF" },
    fill: "#1F4E78",
  };

  summary.freezePanes.freezeRows(11);
  cases.freezePanes.freezeRows(1);

  summary.getRange("A:A").format.columnWidthPx = 95;
  summary.getRange("B:B").format.columnWidthPx = 260;
  summary.getRange("C:C").format.columnWidthPx = 110;
  summary.getRange("D:J").format.columnWidthPx = 95;
  summary.getRange("A26:G26").format.rowHeightPx = 40;
  summary.getRange("A3:G26").format.wrapText = true;
  summary.getRange("A3:G26").format.verticalAlignment = "top";
  summary.getRange("E:E").format.columnWidthPx = 220;
  summary.getRange("F:F").format.columnWidthPx = 95;
  summary.getRange("G:G").format.columnWidthPx = 220;

  cases.getRange("A:A").format.columnWidthPx = 70;
  cases.getRange("B:B").format.columnWidthPx = 180;
  cases.getRange("C:C").format.columnWidthPx = 230;
  cases.getRange("D:D").format.columnWidthPx = 120;
  cases.getRange("E:E").format.columnWidthPx = 90;
  cases.getRange("F:F").format.columnWidthPx = 75;
  cases.getRange("G:G").format.columnWidthPx = 210;
  cases.getRange("H:H").format.columnWidthPx = 180;
  cases.getRange("I:I").format.columnWidthPx = 240;
  cases.getRange("J:J").format.columnWidthPx = 240;
  cases.getRange("K:K").format.columnWidthPx = 260;
  cases.getRange("L:L").format.columnWidthPx = 230;
  cases.getRange("A1:L9").format.wrapText = true;
  cases.getRange("A1:L9").format.verticalAlignment = "top";

  for (let row = 13; row < 13 + results.length; row += 1) {
    const verdict = results[row - 13].verdict;
    const color = verdict === "pass" ? "#E2F0D9" : verdict === "warn" ? "#FFF2CC" : "#FCE4D6";
    summary.getRange(`A${row}:G${row}`).format = { fill: color };
  }
  for (let row = 2; row < 2 + results.length; row += 1) {
    const verdict = results[row - 2].verdict;
    const color = verdict === "pass" ? "#F3FBF0" : verdict === "warn" ? "#FFF9E8" : "#FDF1EE";
    cases.getRange(`A${row}:L${row}`).format = { fill: color };
  }

  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  const out = await SpreadsheetFile.exportXlsx(workbook);
  await out.save(outputPath);
  return outputPath;
}

async function main() {
  const [runJsonPathArg, outputPathArg] = process.argv.slice(2);
  if (!runJsonPathArg || !outputPathArg) {
    usage();
    process.exit(1);
  }
  const builtPath = await buildTracker(runJsonPathArg, outputPathArg);
  console.log(builtPath);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await main();
}
