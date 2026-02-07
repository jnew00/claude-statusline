#!/usr/bin/env node
/**
 * Claude Plan Usage Fetcher (OAuth API)
 *
 * Fetches usage percentages from Anthropic OAuth API using stored credentials.
 * Much simpler than web scraping - no browser needed!
 *
 * Reads credentials from: ~/.cli-proxy-api/claude-*.json
 * Writes output to: ~/.claude/plan-usage.json
 *
 * Usage:
 *   npx tsx src/claude-plan-usage.ts [--daemon] [--interval 600]
 */

import * as fs from "fs";
import * as path from "path";
import * as os from "os";

// ─────────────────────────────────────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────────────────────────────────────

const AUTH_DIR = path.join(os.homedir(), ".cli-proxy-api");
const OUTPUT_PATH = process.env.OUTPUT_DIR
  ? path.join(process.env.OUTPUT_DIR, "plan-usage.json")
  : path.join(os.homedir(), ".claude", "plan-usage.json");
const API_URL = "https://api.anthropic.com/api/oauth/usage";

// ─────────────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────────────

interface AuthFile {
  access_token: string;
  email: string;
  expired?: string;
  refresh_token?: string;
}

interface OAuthUsageResponse {
  five_hour?: {
    utilization: number;
    resets_at: string;
  };
  seven_day?: {
    utilization: number;
    resets_at: string;
  };
  seven_day_sonnet?: {
    utilization: number;
    resets_at: string;
  };
  seven_day_opus?: {
    utilization: number;
    resets_at: string;
  };
  extra_usage?: {
    is_enabled: boolean;
    monthly_limit: number;
    used_credits: number;
    utilization: number;
  };
}

interface UsageData {
  five_hour_percent: number | null;
  weekly_percent: number | null;
  sonnet_percent: number | null;
  opus_percent: number | null;
  extra_percent: number | null;
  resets_in: string | null;
  resets_in_minutes: number | null;
  fetched_at: string;
  email: string | null;
}

interface Config {
  daemon: boolean;
  interval: number; // seconds
}

// ─────────────────────────────────────────────────────────────────────────────
// CLI Argument Parsing
// ─────────────────────────────────────────────────────────────────────────────

function parseArgs(): Config {
  const args = process.argv.slice(2);
  const config: Config = {
    daemon: false,
    interval: 600, // 10 minutes default
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--daemon") {
      config.daemon = true;
    } else if (arg === "--interval" && i + 1 < args.length) {
      config.interval = parseInt(args[i + 1], 10);
      i++;
    } else if (arg === "--help" || arg === "-h") {
      console.log(`
Usage: claude-plan-usage [options]

Options:
  --daemon           Run continuously, refreshing at intervals
  --interval <sec>   Interval between refreshes in daemon mode (default: 600)
  -h, --help         Show this help message

Output written to: ${OUTPUT_PATH}

Example:
  # One-time fetch
  npx tsx src/claude-plan-usage.ts

  # Run as daemon (refresh every 5 minutes)
  npx tsx src/claude-plan-usage.ts --daemon --interval 300
`);
      process.exit(0);
    }
  }

  return config;
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth File Discovery
// ─────────────────────────────────────────────────────────────────────────────

function findAuthFile(): AuthFile | null {
  try {
    if (!fs.existsSync(AUTH_DIR)) {
      console.error(`Auth directory not found: ${AUTH_DIR}`);
      return null;
    }

    const files = fs.readdirSync(AUTH_DIR);
    const claudeFiles = files.filter(
      (f) => f.startsWith("claude-") && f.endsWith(".json")
    );

    if (claudeFiles.length === 0) {
      console.error("No Claude auth files found in ~/.cli-proxy-api/");
      console.error(
        "Please authenticate with Claude Code CLI first: claude auth login"
      );
      return null;
    }

    // Use first auth file found
    const authPath = path.join(AUTH_DIR, claudeFiles[0]);
    const authData = JSON.parse(fs.readFileSync(authPath, "utf-8"));

    if (!authData.access_token) {
      console.error("Auth file missing access_token");
      return null;
    }

    return authData;
  } catch (error) {
    console.error("Error reading auth file:", error);
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// API Fetch
// ─────────────────────────────────────────────────────────────────────────────

async function fetchUsage(accessToken: string): Promise<OAuthUsageResponse | null> {
  try {
    const response = await fetch(API_URL, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "anthropic-beta": "oauth-2025-04-20",
        Accept: "application/json",
      },
    });

    if (!response.ok) {
      console.error(`API error: ${response.status} ${response.statusText}`);
      return null;
    }

    return await response.json();
  } catch (error) {
    console.error("Error fetching usage:", error);
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Time Formatting
// ─────────────────────────────────────────────────────────────────────────────

function formatTimeRemaining(resetsAt: string): {
  formatted: string;
  minutes: number;
} {
  try {
    const resetTime = new Date(resetsAt);
    const now = new Date();
    const diffMs = resetTime.getTime() - now.getTime();

    if (diffMs <= 0) {
      return { formatted: "now", minutes: 0 };
    }

    const minutes = Math.floor(diffMs / 60000);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (days > 0) {
      const remainingHours = hours % 24;
      if (remainingHours > 0) {
        return {
          formatted: `${days}d ${remainingHours}h`,
          minutes,
        };
      }
      return { formatted: `${days}d`, minutes };
    } else if (hours > 0) {
      const remainingMinutes = minutes % 60;
      if (remainingMinutes > 0) {
        return {
          formatted: `${hours}h ${remainingMinutes}m`,
          minutes,
        };
      }
      return { formatted: `${hours}h`, minutes };
    } else {
      return { formatted: `${Math.max(1, minutes)}m`, minutes };
    }
  } catch (error) {
    return { formatted: "unknown", minutes: 0 };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Logic
// ─────────────────────────────────────────────────────────────────────────────

async function scrapeUsage(): Promise<void> {
  const auth = findAuthFile();
  if (!auth) {
    process.exit(1);
  }

  console.log(`Using auth for: ${auth.email}`);

  const usage = await fetchUsage(auth.access_token);
  if (!usage) {
    console.error("Failed to fetch usage data");
    process.exit(1);
  }

  // Calculate remaining percentages (100 - utilization)
  const fiveHourPercent = usage.five_hour
    ? Math.floor(100 - usage.five_hour.utilization)
    : null;
  const weeklyPercent = usage.seven_day
    ? Math.floor(100 - usage.seven_day.utilization)
    : null;
  const sonnetPercent = usage.seven_day_sonnet
    ? Math.floor(100 - usage.seven_day_sonnet.utilization)
    : null;
  const opusPercent = usage.seven_day_opus
    ? Math.floor(100 - usage.seven_day_opus.utilization)
    : null;
  const extraPercent =
    usage.extra_usage && usage.extra_usage.is_enabled
      ? Math.floor(100 - usage.extra_usage.utilization)
      : null;

  // Use five_hour reset time for "resets_in"
  let resetsIn: string | null = null;
  let resetsInMinutes: number | null = null;
  if (usage.five_hour?.resets_at) {
    const timeRemaining = formatTimeRemaining(usage.five_hour.resets_at);
    resetsIn = timeRemaining.formatted;
    resetsInMinutes = timeRemaining.minutes;
  }

  const outputData: UsageData = {
    five_hour_percent: fiveHourPercent,
    weekly_percent: weeklyPercent,
    sonnet_percent: sonnetPercent,
    opus_percent: opusPercent,
    extra_percent: extraPercent,
    resets_in: resetsIn,
    resets_in_minutes: resetsInMinutes,
    fetched_at: new Date().toISOString(),
    email: auth.email,
  };

  // Ensure output directory exists
  const outputDir = path.dirname(OUTPUT_PATH);
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  // Write output
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(outputData, null, 2));

  console.log(`✓ Usage data written to: ${OUTPUT_PATH}`);
  console.log(
    `  5-hour: ${fiveHourPercent}% remaining, weekly: ${weeklyPercent}% remaining`
  );
  if (resetsIn) {
    console.log(`  Resets in: ${resetsIn}`);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry Point
// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  const config = parseArgs();

  if (config.daemon) {
    console.log(
      `Running in daemon mode (refresh every ${config.interval} seconds)...`
    );
    console.log("Press Ctrl+C to stop\n");

    // Run immediately on start
    await scrapeUsage();

    // Then run on interval
    setInterval(async () => {
      console.log("\n" + new Date().toISOString());
      await scrapeUsage();
    }, config.interval * 1000);

    // Keep process alive
    await new Promise(() => {});
  } else {
    // One-time run
    await scrapeUsage();
  }
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
