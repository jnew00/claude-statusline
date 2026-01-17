You are an expert macOS automation engineer and Node/TypeScript developer. Goal: build the most robust, low-maintenance way on macOS to periodically fetch my Anthropic Claude Max plan usage percentages (5-hour window and weekly) from the authenticated web UI and write them to ~/.claude/plan-usage.json. This is for use in a shell statusline.
Context and constraints
	•	OS: macOS (Apple Silicon, recent macOS).
	•	Browser: Chrome is installed and used daily.
	•	Plan: Claude Max 5x (consumer subscription). The only place these usage percentages exist is the authenticated web UI at: https://platform.claude.com/settings/usage
	•	Authentication:
	•	There is no public API for consumer Max usage.
	•	I log in through Chrome; I want the automation to reuse my existing logged-in state, not store a separate password or token.
Requirements
	1.	Use Playwright with Node or TypeScript (your choice, but be consistent).
	2.	Reuse my existing Chrome profile or its cookies so I stay logged in with minimal friction.
	3.	Run headless (or nearly so) with no or minimal visual disruption.
	4.	Handle normal real-world flakiness:
	•	Page load delays / slow network.
	•	Occasional auth prompts (e.g. if the session is expired).
	•	DOM changes that don’t fully redesign the page.
	5.	Run automatically at intervals on macOS using launchd (not just cron), with logs to a file.
	6.	Write a JSON file with a stable shape to ~/.claude/plan-usage.json:
{ “five_hour_percent”: 34.5, “weekly_percent”: 62.0, “raw”: { “five_hour”: “34.5% of 5-hour window used”, “weekly”: “62% of weekly limit used” }, “fetched_at”: “2026-01-17T15:30:00.000Z” }
What to produce
	1.	Project layout and setup
	•	Choose either pure Node (JavaScript) or TypeScript. Pick one and stick with it.
	•	Provide:
	•	package.json with all dependencies (Playwright, any helpers).
	•	Installation commands for macOS (using npm).
	•	If you pick TypeScript, include a tsconfig.json.
	2.	Authentication and browser launching strategy (choose the most robust option)
Pick the most robust, production-worthy approach and implement it end-to-end. Options to consider:
	•	Playwright launchPersistentContext + Chrome user profile: Reuse my existing Chrome profile directory so cookies and sessions are preserved.
	•	OR: Read Chrome cookies on macOS and inject them into a fresh Playwright context.
Whichever you choose, you must:
	•	Detect or allow configuration of the Chrome user data directory and profile name on macOS (for example: ~/Library/Application Support/Google/Chrome/Default).
	•	Provide a simple way to override the profile name via a config or environment variable if I don’t use “Default”.
	•	Fail with a clear error message if the profile path doesn’t exist.
	•	Launch in headless mode by default but allow a debug flag (for example: –headed) to run with a visible window.
	3.	Usage scraping logic
Implement the main script file (claude-plan-usage.js or claude-plan-usage.ts) that:
	1.	Starts the Playwright browser using the chosen auth strategy.
	2.	Navigates to: https://platform.claude.com/settings/usage and waits robustly for the page to be ready (for example: networkidle plus a specific, stable element).
	3.	Locates the 5-hour window and weekly usage values using resilient selectors:
	•	Prefer selectors anchored on stable text labels like “5-hour rolling window” and “Weekly usage”.
	•	From these labels, traverse to the actual numeric percentage element.
	•	Avoid brittle selectors based only on auto-generated class names.
	4.	Parses percentage values from strings like “34% used” into numbers like 34.
	5.	Constructs the JSON object in the schema shown above and writes it to: ~/.claude/plan-usage.json
	•	Ensure the ~/.claude directory exists.
Include:
	•	Reasonable timeouts and at least one automatic retry on transient failure (for example: a simple “retry once if navigation or selector wait fails”).
	•	Clear console logging for success and failure.
	•	Non-zero exit codes on failure.
	4.	Handling auth expiry gracefully
Implement behavior such that:
	•	If the script ends up on a login screen instead of the usage page, it:
	•	Detects this state (for example: presence of an email/password field, “Sign in” text, or a known login container).
	•	Exits with a clear, user-friendly message such as: “Not logged in – please open Chrome, log into https://platform.claude.com, then rerun this script.”
	•	Does NOT attempt to automate credentials entry.
Document in comments or readme text how I re-establish the session once (by logging in manually in Chrome), after which the automation can continue to function.
	5.	macOS launchd integration
Provide a complete launchd plist that lives at:
~/Library/LaunchAgents/com.username.claude-plan-usage.plist
(Use a placeholder “username” that I can replace.)
This plist should:
	•	Run the Node script every N minutes (for example: every 10 or 15 minutes).
	•	Use an absolute path to the node binary and the script.
	•	Set stdout and stderr paths to something like: ~/Library/Logs/claude-plan-usage.log
	•	Ensure the working directory is sensible (for example: the project directory or my home directory).
Also include exact Terminal commands to:
	•	Validate the plist: plutil -lint ~/Library/LaunchAgents/com.username.claude-plan-usage.plist
	•	Load and start it (for a user agent) on modern macOS: launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.username.claude-plan-usage.plist launchctl kickstart -k gui/$(id -u)/com.username.claude-plan-usage
	•	Unload/disable it: launchctl bootout gui/$(id -u)/com.username.claude-plan-usage
Mention any macOS-specific gotchas, such as:
	•	The need for absolute paths.
	•	PATH not being inherited like an interactive shell.
	•	Where the log file will appear and how to tail it.
	6.	Developer ergonomics helper
Add a small helper script at:
bin/claude-plan-usage-status
This helper should:
	•	Read ~/.claude/plan-usage.json.
	•	Print a single-line status string suitable for a shell prompt or tmux statusline. For example:
C5h:34% Wk:62%
You can implement this helper either as:
	•	A Node/TypeScript script, or
	•	A POSIX shell script using jq.
Pick one and include the complete code.
	7.	One-time setup instructions
At the end of your answer, provide a concise, numbered checklist that I can follow to get everything working from scratch on macOS, including:
	1.	Commands to install dependencies (Node, npm, Playwright).
	2.	How to confirm Playwright can see and reuse my Chrome profile (one quick test command).
	3.	How to run the script once manually (optionally in headed mode) to verify that:
	•	It logs in via existing cookies.
	•	The selectors correctly pick up the two percentage values.
	•	~/.claude/plan-usage.json is created with the expected shape.
	4.	How to install and enable the launchd job.
	5.	How to wire bin/claude-plan-usage-status into:
	•	A zsh prompt (for example, using PROMPT or RPROMPT), or
	•	A tmux statusline.
Important style constraints
	•	Produce fully working, cohesive code. No placeholders like “pseudo-code here”.
	•	Use sensible defaults that work for a typical macOS Chrome user with a “Default” profile.
	•	Keep comments focused on key design decisions and macOS-specific quirks.
	•	Prefer clarity and robustness over minimalism – a few extra lines are fine if they make the automation more stable over time.
Now generate all of the following, in one coherent project:
	•	package.json
	•	(Optional) tsconfig.json if you use TypeScript
	•	Main script: claude-plan-usage.js or claude-plan-usage.ts
	•	Helper script: bin/claude-plan-usage-status
	•	launchd plist: com.username.claude-plan-usage.plist
	•	A short “setup checklist” section with the exact commands and steps described above.