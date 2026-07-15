const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const INSTALL_SCRIPT = path.resolve(__dirname, "..", "bin", "install.js");

function makeFakeHome() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "claude-statusline-test-"));
}

function runUninstall(fakeHome) {
  execFileSync(process.execPath, [INSTALL_SCRIPT, "--uninstall"], {
    env: { ...process.env, HOME: fakeHome, USERPROFILE: fakeHome },
    stdio: "pipe",
  });
}

function settingsPath(fakeHome) {
  return path.join(fakeHome, ".claude", "settings.json");
}

function writeSettings(fakeHome, settings) {
  const claudeDir = path.join(fakeHome, ".claude");
  fs.mkdirSync(claudeDir, { recursive: true });
  fs.writeFileSync(settingsPath(fakeHome), JSON.stringify(settings, null, 2) + "\n");
}

test("uninstall removes only statusLine, leaving other settings untouched", () => {
  const fakeHome = makeFakeHome();
  try {
    const original = {
      statusLine: { type: "command", command: "bash \"$HOME/.claude/statusline.sh\"" },
      model: "claude-sonnet-5",
      permissions: { allow: ["Bash(git *)"], deny: [] },
      env: { FOO: "bar" },
    };
    writeSettings(fakeHome, original);

    runUninstall(fakeHome);

    const result = JSON.parse(fs.readFileSync(settingsPath(fakeHome), "utf-8"));

    assert.equal("statusLine" in result, false, "statusLine key should be removed");

    const { statusLine, ...expectedRest } = original;
    assert.deepEqual(result, expectedRest, "all non-statusLine keys must be preserved exactly");
  } finally {
    fs.rmSync(fakeHome, { recursive: true, force: true });
  }
});

test("uninstall is a no-op on settings.json when statusLine key is absent", () => {
  const fakeHome = makeFakeHome();
  try {
    const original = {
      model: "claude-sonnet-5",
      permissions: { allow: [], deny: [] },
    };
    writeSettings(fakeHome, original);

    runUninstall(fakeHome);

    const result = JSON.parse(fs.readFileSync(settingsPath(fakeHome), "utf-8"));
    assert.deepEqual(result, original, "settings.json must be unchanged when there is no statusLine key");
  } finally {
    fs.rmSync(fakeHome, { recursive: true, force: true });
  }
});

test("uninstall does not touch settings.json when the file does not exist", () => {
  const fakeHome = makeFakeHome();
  try {
    runUninstall(fakeHome);
    assert.equal(fs.existsSync(settingsPath(fakeHome)), false, "settings.json should not be created by uninstall");
  } finally {
    fs.rmSync(fakeHome, { recursive: true, force: true });
  }
});
