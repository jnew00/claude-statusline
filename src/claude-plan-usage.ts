#!/usr/bin/env node
/**
 * Claude Max Plan Usage Scraper
 *
 * Scrapes usage percentages from the Claude web UI using Playwright
 * with a dedicated persistent profile for authentication.
 *
 * First run: Use --headed to log in manually, session will be saved
 * Subsequent runs: Reuses saved session automatically
 *
 * Usage:
 *   npx tsx src/claude-plan-usage.ts [--headed]
 */

import { chromium, type BrowserContext, type Page } from "playwright";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import { exec } from "child_process";

// ─────────────────────────────────────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────────────────────────────────────

const USAGE_URL = "https://claude.ai/settings/usage";
const OUTPUT_PATH = process.env.OUTPUT_DIR
  ? path.join(process.env.OUTPUT_DIR, "plan-usage.json")
  : path.join(os.homedir(), ".claude", "plan-usage.json");
const PLAYWRIGHT_PROFILE_DIR = process.env.PROFILE_DIR
  || process.env.PLAYWRIGHT_PROFILE_DIR
  || path.join(os.homedir(), ".claude", "playwright-profile");
const MAX_RETRIES = 1;
const NAVIGATION_TIMEOUT = 30_000;

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

interface UsageData {
  five_hour_percent: number | null;
  weekly_percent: number | null;
  resets_in: string | null;
  resets_in_minutes: number | null;
  raw: {
    five_hour: string | null;
    weekly: string | null;
  };
  fetched_at: string;
}

interface Config {
  headed: boolean;
  loginOnly: boolean;
}

// ─────────────────────────────────────────────────────────────────────────────
// CLI Argument Parsing
// ─────────────────────────────────────────────────────────────────────────────

function parseArgs(): Config {
  const args = process.argv.slice(2);
  const config: Config = {
    headed: false,
    loginOnly: false,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--headed") {
      config.headed = true;
    } else if (arg === "--login") {
      config.loginOnly = true;
      config.headed = true; // login mode is always headed
    } else if (arg === "--help" || arg === "-h") {
      console.log(`
Usage: claude-plan-usage [options]

Options:
  --login     LOGIN MODE: Opens browser, waits for you to log in, then exits.
              Browser stays open as long as needed. Press Enter when done.
  --headed    Run with visible browser window
  -h, --help  Show this help message

Profile stored at: ${PLAYWRIGHT_PROFILE_DIR}
Output written to: ${OUTPUT_PATH}

First run:
  npm run dev -- --login
  Log into claude.ai, press Enter in terminal when done.

Subsequent runs:
  npm run dev
`);
      process.exit(0);
    }
  }

  return config;
}

// ─────────────────────────────────────────────────────────────────────────────
// Utilities
// ─────────────────────────────────────────────────────────────────────────────

function log(message: string): void {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] ${message}`);
}

/**
 * Move browser window off-screen using CDP and minimize via AppleScript
 */
async function hideWindow(context: BrowserContext, page: Page): Promise<void> {
  try {
    // First move off-screen via CDP
    const session = await context.newCDPSession(page);
    const { windowId } = await session.send("Browser.getWindowForTarget");
    await session.send("Browser.setWindowBounds", {
      windowId,
      bounds: { left: -2000, top: 0, width: 800, height: 600 },
    });
    log("Window moved off-screen via CDP");

    // Then minimize via AppleScript (belt and suspenders)
    const script = `
      tell application "System Events"
        set chromeProcs to every process whose name contains "Chromium" or name contains "chrome"
        repeat with proc in chromeProcs
          try
            set miniaturized of every window of proc to true
          end try
        end repeat
      end tell
    `;
    exec(`osascript -e '${script}'`, (err) => {
      if (err) {
        log(`AppleScript minimize failed: ${err.message}`);
      } else {
        log("Window minimized via AppleScript");
      }
    });
  } catch (err) {
    log(`Failed to hide window: ${err}`);
  }
}

function logError(message: string): void {
  const timestamp = new Date().toISOString();
  console.error(`[${timestamp}] ERROR: ${message}`);
}

/**
 * Ensure the output directory exists
 */
function ensureOutputDir(): void {
  const dir = path.dirname(OUTPUT_PATH);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
    log(`Created directory: ${dir}`);
  }
}

/**
 * Write usage data to JSON file
 */
function writeUsageData(data: UsageData): void {
  ensureOutputDir();
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(data, null, 2) + "\n");
  log(`Wrote usage data to ${OUTPUT_PATH}`);
}

// ─────────────────────────────────────────────────────────────────────────────
// Browser & Scraping Logic
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Check if we're on a login page instead of the usage page
 */
async function isOnLoginPage(page: Page): Promise<boolean> {
  const url = page.url();

  // Check URL first
  if (
    url.includes("/login") ||
    url.includes("/signin") ||
    url.includes("/auth") ||
    url.includes("accounts.google.com") ||
    !url.includes("claude.ai/settings")
  ) {
    return true;
  }

  // Check for login form elements
  const loginIndicators = [
    'input[type="email"]',
    'input[type="password"]',
    'button:has-text("Sign in")',
    'button:has-text("Log in")',
  ];

  for (const selector of loginIndicators) {
    try {
      const element = await page.$(selector);
      if (element) {
        return true;
      }
    } catch {
      // Selector not found, continue
    }
  }

  return false;
}

/**
 * Wait for user to log in manually - NO TIMEOUT
 */
async function waitForManualLogin(page: Page): Promise<void> {
  log("");
  log("═══════════════════════════════════════════════════════════════");
  log("  LOGIN REQUIRED - TAKE YOUR TIME");
  log("═══════════════════════════════════════════════════════════════");
  log("");
  log("  Please log into claude.ai in the browser window.");
  log("  Once logged in, the script will detect it automatically.");
  log("");
  log("  The browser will stay open until you're logged in.");
  log("  Press Ctrl+C in terminal to cancel.");
  log("");
  log("═══════════════════════════════════════════════════════════════");
  log("");

  // Poll until we're logged in - no timeout
  let checkCount = 0;
  while (true) {
    await page.waitForTimeout(3000);
    checkCount++;

    if (checkCount % 10 === 0) {
      log("Still waiting for login...");
    }

    const url = page.url();

    // Success: on the usage page
    if (url.includes("claude.ai/settings/usage")) {
      log("Detected usage page, continuing...");
      break;
    }

    // Logged in but not on usage page yet
    if (url.includes("claude.ai") && !url.includes("login") && !url.includes("accounts.google") && !url.includes("oauth")) {
      log("Logged in! Navigating to usage page...");
      try {
        await page.goto(USAGE_URL, { waitUntil: "domcontentloaded", timeout: 15000 });
        await page.waitForTimeout(2000);
        if (page.url().includes("claude.ai/settings/usage")) {
          log("Successfully navigated to usage page");
          break;
        }
      } catch {
        log("Navigation attempt failed, will retry...");
      }
    }
  }
}

/**
 * Scrape usage data from the page
 */
async function scrapeUsageData(page: Page): Promise<UsageData> {
  const data: UsageData = {
    five_hour_percent: null,
    weekly_percent: null,
    resets_in: null,
    resets_in_minutes: null,
    raw: {
      five_hour: null,
      weekly: null,
    },
    fetched_at: new Date().toISOString(),
  };

  try {
    // Wait for page to load (don't use networkidle - SPAs never go idle)
    await page.waitForLoadState("domcontentloaded", { timeout: NAVIGATION_TIMEOUT });

    // Wait for content to appear - look for any percentage on page
    log("Waiting for usage data to appear...");
    await page.waitForFunction(
      () => document.body?.textContent?.match(/\d+%/),
      { timeout: NAVIGATION_TIMEOUT }
    );

    // Small delay for React to finish rendering
    await page.waitForTimeout(1000);

    const pageContent = await page.textContent("body");

    if (!pageContent) {
      throw new Error("Page has no text content");
    }

    log("Page loaded, searching for usage data...");

    // Find all percentages on the page
    const allPercentages = pageContent.match(/\d+(?:\.\d+)?%/g) || [];

    // Strategy: Look for sections containing "session" (5-hour) and "daily" (daily limit)
    // The page shows "Current session" for 5-hour and might show daily limits

    // Try to find session/5-hour usage
    const sessionMatch = pageContent.match(/(?:current\s+session|5.?hour)[^]*?([\d.]+)%/i);
    if (sessionMatch) {
      data.five_hour_percent = parseFloat(sessionMatch[1]);
      data.raw.five_hour = sessionMatch[0].substring(0, 100).trim();
      log(`Found session usage: ${data.five_hour_percent}%`);
    }

    // Try to find daily/weekly usage
    const dailyMatch = pageContent.match(/(?:daily|weekly)[^]*?([\d.]+)%/i);
    if (dailyMatch) {
      data.weekly_percent = parseFloat(dailyMatch[1]);
      data.raw.weekly = dailyMatch[0].substring(0, 100).trim();
      log(`Found daily/weekly usage: ${data.weekly_percent}%`);
    }

    // Fallback: if we only have percentages, try to assign them
    if (data.five_hour_percent === null && allPercentages[0]) {
      data.five_hour_percent = parseFloat(allPercentages[0]);
      data.raw.five_hour = allPercentages[0];
      log(`Fallback 5-hour: ${data.five_hour_percent}%`);
    }
    if (data.weekly_percent === null && allPercentages[1]) {
      data.weekly_percent = parseFloat(allPercentages[1]);
      data.raw.weekly = allPercentages[1];
      log(`Fallback weekly: ${data.weekly_percent}%`);
    }

    // Parse reset time (e.g., "Resets in 2 hr 40 min" or "Resets in 45 min")
    const resetMatch = pageContent.match(/resets?\s+in\s+((\d+)\s*hr?)?\s*((\d+)\s*min)?/i);
    if (resetMatch) {
      const hours = resetMatch[2] ? parseInt(resetMatch[2]) : 0;
      const minutes = resetMatch[4] ? parseInt(resetMatch[4]) : 0;
      data.resets_in_minutes = hours * 60 + minutes;

      // Format as human readable
      if (hours > 0 && minutes > 0) {
        data.resets_in = `${hours}h ${minutes}m`;
      } else if (hours > 0) {
        data.resets_in = `${hours}h`;
      } else {
        data.resets_in = `${minutes}m`;
      }
      log(`Found reset time: ${data.resets_in} (${data.resets_in_minutes} minutes)`);
    }

    if (data.five_hour_percent === null && data.weekly_percent === null) {
      throw new Error("Could not find any usage percentages on the page");
    }

  } catch (error) {
    throw new Error(`Failed to scrape usage data: ${error}`);
  }

  return data;
}

/**
 * Main scraping function with retry logic
 */
async function scrapeWithRetry(config: Config): Promise<UsageData> {
  log(`Using Playwright profile: ${PLAYWRIGHT_PROFILE_DIR}`);

  // Ensure profile directory exists
  if (!fs.existsSync(PLAYWRIGHT_PROFILE_DIR)) {
    fs.mkdirSync(PLAYWRIGHT_PROFILE_DIR, { recursive: true });
    log("Created new Playwright profile directory");
  }

  let lastError: Error | null = null;
  const maxAttempts = config.headed ? 1 : MAX_RETRIES + 1; // No retries in headed mode

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    if (attempt > 0) {
      log(`Retry attempt ${attempt}/${MAX_RETRIES}...`);
      await new Promise((resolve) => setTimeout(resolve, 3000));
    }

    let context: BrowserContext | null = null;

    try {
      log(`Launching browser (headed: ${config.headed})...`);

      context = await chromium.launchPersistentContext(PLAYWRIGHT_PROFILE_DIR, {
        headless: false, // Must be headed to bypass Cloudflare
        args: [
          "--disable-blink-features=AutomationControlled",
          "--no-first-run",
          "--disable-dev-shm-usage",
          "--disable-session-crashed-bubble",
          "--disable-infobars",
          "--noerrdialogs",
          "--hide-crash-restore-bubble",
          "--no-sandbox",
          "--disable-setuid-sandbox",
          "--disable-gpu",
        ],
        ignoreDefaultArgs: ["--enable-automation"],
        viewport: config.headed ? null : { width: 800, height: 600 },
        timeout: 60_000,
      });

      log("Browser launched");

      const page = context.pages()[0] || (await context.newPage());

      // Hide window if not in headed mode
      if (!config.headed) {
        await hideWindow(context, page);
      }

      log(`Navigating to ${USAGE_URL}...`);
      await page.goto(USAGE_URL, {
        waitUntil: "domcontentloaded",
        timeout: NAVIGATION_TIMEOUT,
      });

      log(`Current URL: ${page.url()}`);

      // Check if login is needed
      if (await isOnLoginPage(page)) {
        if (!config.headed) {
          logError("Not logged in. Run with --headed to log in manually.");
          await context.close();
          process.exit(2);
        }

        await waitForManualLogin(page);
      }

      // Scrape the data
      const data = await scrapeUsageData(page);

      await context.close();
      return data;

    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      logError(`Attempt ${attempt + 1} failed: ${lastError.message}`);

      if (context) {
        try {
          await context.close();
        } catch {
          // Ignore
        }
      }
    }
  }

  throw lastError || new Error("Unknown error during scraping");
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Entry Point
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Login-only mode: just open browser and wait for Enter key
 */
async function loginOnlyMode(): Promise<void> {
  log(`Using Playwright profile: ${PLAYWRIGHT_PROFILE_DIR}`);

  if (!fs.existsSync(PLAYWRIGHT_PROFILE_DIR)) {
    fs.mkdirSync(PLAYWRIGHT_PROFILE_DIR, { recursive: true });
  }

  log("Launching browser for login...");

  const context = await chromium.launchPersistentContext(PLAYWRIGHT_PROFILE_DIR, {
    headless: false,
    args: [
      "--disable-blink-features=AutomationControlled",
      "--no-first-run",
      "--no-sandbox",
      "--disable-setuid-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu",
      "--window-position=0,0",
      "--window-size=1200,700",
    ],
    timeout: 0, // No timeout
  });

  const page = context.pages()[0] || (await context.newPage());

  await page.goto("https://claude.ai", { waitUntil: "domcontentloaded", timeout: 60000 });

  log("");
  log("═══════════════════════════════════════════════════════════════");
  log("  BROWSER OPEN - LOG IN NOW");
  log("═══════════════════════════════════════════════════════════════");
  log("");
  log("  1. Log into claude.ai in the browser window");
  log("  2. Take as long as you need");
  log("  3. When done, press ENTER here to save session and exit");
  log("");
  log("═══════════════════════════════════════════════════════════════");
  log("");

  // Wait for Enter key
  await new Promise<void>((resolve) => {
    process.stdin.setRawMode?.(false);
    process.stdin.resume();
    process.stdin.once("data", () => resolve());
  });

  log("Saving session and closing browser...");
  await context.close();
  log("Session saved! You can now run without --login");
}

async function main(): Promise<void> {
  log("Claude Plan Usage Scraper starting...");

  const config = parseArgs();

  // Login-only mode
  if (config.loginOnly) {
    await loginOnlyMode();
    process.exit(0);
  }

  try {
    const data = await scrapeWithRetry(config);

    log("Successfully scraped usage data:");
    log(`  5-hour window: ${data.five_hour_percent ?? "N/A"}%`);
    log(`  Weekly: ${data.weekly_percent ?? "N/A"}%`);
    log(`  Resets in: ${data.resets_in ?? "N/A"}`);

    writeUsageData(data);

    log("Done!");
    process.exit(0);

  } catch (error) {
    logError(`Fatal error: ${error}`);
    process.exit(1);
  }
}

main();
