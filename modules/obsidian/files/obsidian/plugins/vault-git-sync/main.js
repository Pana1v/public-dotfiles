// Vault Git Sync: commit, pull and push the vault using the host git and
// its gh credential helper. Inside the Flatpak sandbox git cannot see the
// host gh, so every git call goes through `flatpak-spawn --host`.
const { Plugin, PluginSettingTab, Setting, Notice, FileSystemAdapter } = require("obsidian");
const { execFile } = require("child_process");
const fs = require("fs");
const os = require("os");

const DEFAULTS = {
	syncAfterChangeMin: 5,
	intervalMin: 30,
	pullOnStartup: true,
	commitMessage: "auto({{host}}): {{date}}",
};

// Git must fail fast instead of opening a login dialog.
const QUIET_ENV = {
	GIT_TERMINAL_PROMPT: "0",
	GIT_ASKPASS: "true",
	SSH_ASKPASS: "true",
	GCM_INTERACTIVE: "never",
};

const IN_FLATPAK = fs.existsSync("/.flatpak-info");

function stamp() {
	const d = new Date();
	const p = (n) => String(n).padStart(2, "0");
	return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

module.exports = class VaultGitSync extends Plugin {
	async onload() {
		this.settings = Object.assign({}, DEFAULTS, await this.loadData());
		const adapter = this.app.vault.adapter;
		if (!(adapter instanceof FileSystemAdapter)) {
			new Notice("Vault Git Sync: desktop vaults only.");
			return;
		}
		this.cwd = adapter.getBasePath();
		this.busy = false;
		this.pending = false;
		this.debounce = null;

		this.status = this.addStatusBarItem();
		this.status.addClass("mod-clickable");
		this.status.onClickEvent(() => this.sync(true));
		this.setStatus("git: idle");

		this.addCommand({ id: "sync", name: "Sync now (commit, pull, push)", callback: () => this.sync(true) });
		this.addCommand({ id: "pull", name: "Pull", callback: () => this.pull(true) });
		this.addCommand({ id: "status", name: "Show git status", callback: () => this.showStatus() });
		this.addSettingTab(new SyncSettings(this));

		this.registerEvent(this.app.vault.on("modify", () => this.schedule()));
		this.registerEvent(this.app.vault.on("create", () => this.schedule()));
		this.registerEvent(this.app.vault.on("delete", () => this.schedule()));
		this.registerEvent(this.app.vault.on("rename", () => this.schedule()));
		this.resetInterval();

		this.app.workspace.onLayoutReady(() => {
			if (this.settings.pullOnStartup) this.pull(false);
		});
	}

	onunload() {
		clearTimeout(this.debounce);
	}

	resetInterval() {
		if (this.timer) window.clearInterval(this.timer);
		this.timer = null;
		if (this.settings.intervalMin > 0) {
			this.timer = window.setInterval(() => this.sync(false), this.settings.intervalMin * 60000);
			this.registerInterval(this.timer);
		}
	}

	schedule() {
		if (this.settings.syncAfterChangeMin <= 0) return;
		clearTimeout(this.debounce);
		this.debounce = setTimeout(() => this.sync(false), this.settings.syncAfterChangeMin * 60000);
	}

	git(args, timeout = 120000) {
		const envFlags = Object.entries(QUIET_ENV).map(([k, v]) => `--env=${k}=${v}`);
		const [bin, argv] = IN_FLATPAK
			? ["flatpak-spawn", ["--host", `--directory=${this.cwd}`, ...envFlags, "git", ...args]]
			: ["git", args];
		const env = Object.assign({}, process.env, QUIET_ENV);
		return new Promise((resolve) => {
			execFile(bin, argv, { cwd: this.cwd, env, timeout, encoding: "utf8", maxBuffer: 16 << 20 }, (err, stdout, stderr) => {
				resolve({ ok: !err, out: (stdout || "").trim(), err: (stderr || err?.message || "").trim() });
			});
		});
	}

	setStatus(text) {
		this.status?.setText(text);
	}

	fail(step, res) {
		const msg = res.err.split("\n").slice(-3).join("\n");
		console.error(`vault-git-sync: ${step} failed`, res.err);
		new Notice(`Git ${step} failed:\n${msg}`, 10000);
		this.setStatus(`git: ${step} failed`);
	}

	async locked(fn) {
		if (this.busy) {
			this.pending = true;
			return;
		}
		this.busy = true;
		try {
			await fn();
		} finally {
			this.busy = false;
			if (this.pending) {
				this.pending = false;
				this.schedule();
			}
		}
	}

	async conflicted() {
		const res = await this.git(["diff", "--name-only", "--diff-filter=U"]);
		return res.ok && res.out.length > 0;
	}

	async pullInner() {
		this.setStatus("git: pulling");
		const res = await this.git(["pull", "--no-rebase", "--no-edit"]);
		if (!res.ok) {
			if (await this.conflicted()) {
				new Notice("Git pull hit merge conflicts. Resolve them, then run 'Sync now'.", 0);
				this.setStatus("git: conflicts");
			} else this.fail("pull", res);
			return false;
		}
		return true;
	}

	pull(manual) {
		return this.locked(async () => {
			if (await this.pullInner()) {
				this.setStatus(`git: pulled ${stamp().slice(11, 16)}`);
				if (manual) new Notice("Git: pulled.");
			}
		});
	}

	sync(manual) {
		clearTimeout(this.debounce);
		return this.locked(async () => {
			if (await this.conflicted()) {
				new Notice("Git: unresolved conflicts, sync skipped.");
				this.setStatus("git: conflicts");
				return;
			}
			this.setStatus("git: committing");
			let res = await this.git(["add", "-A"]);
			if (!res.ok) return this.fail("add", res);

			res = await this.git(["status", "--porcelain"]);
			if (!res.ok) return this.fail("status", res);
			const changed = res.out ? res.out.split("\n").length : 0;
			if (changed) {
				const msg = this.settings.commitMessage
					.replace("{{host}}", os.hostname())
					.replace("{{date}}", stamp());
				res = await this.git(["commit", "-q", "-m", msg]);
				if (!res.ok) return this.fail("commit", res);
			}

			if (!(await this.pullInner())) return;

			res = await this.git(["rev-list", "--count", "@{u}..HEAD"]);
			const ahead = res.ok ? parseInt(res.out, 10) || 0 : 1;
			if (ahead > 0) {
				this.setStatus("git: pushing");
				res = await this.git(["push"]);
				if (!res.ok) return this.fail("push", res);
			}

			this.setStatus(`git: synced ${stamp().slice(11, 16)}`);
			if (manual) new Notice(changed || ahead ? `Git: synced ${changed} file(s), pushed ${ahead} commit(s).` : "Git: already up to date.");
		});
	}

	async showStatus() {
		const res = await this.git(["status", "-sb"]);
		new Notice(res.ok ? res.out || "clean" : res.err, 10000);
	}

	async saveSettings() {
		await this.saveData(this.settings);
		this.resetInterval();
	}
};

class SyncSettings extends PluginSettingTab {
	constructor(plugin) {
		super(plugin.app, plugin);
		this.plugin = plugin;
	}

	display() {
		const { containerEl } = this;
		const s = this.plugin.settings;
		containerEl.empty();

		const num = (name, desc, key) =>
			new Setting(containerEl).setName(name).setDesc(desc).addText((t) =>
				t.setValue(String(s[key])).onChange(async (v) => {
					const n = Number(v);
					if (!Number.isFinite(n) || n < 0) return;
					s[key] = n;
					await this.plugin.saveSettings();
				})
			);

		num("Sync after edits (minutes)", "Quiet period after the last change before syncing. 0 disables.", "syncAfterChangeMin");
		num("Periodic sync (minutes)", "Sync on a fixed interval as well. 0 disables.", "intervalMin");

		new Setting(containerEl).setName("Pull on startup").addToggle((t) =>
			t.setValue(s.pullOnStartup).onChange(async (v) => {
				s.pullOnStartup = v;
				await this.plugin.saveSettings();
			})
		);

		new Setting(containerEl)
			.setName("Commit message")
			.setDesc("{{host}} and {{date}} are replaced.")
			.addText((t) =>
				t.setValue(s.commitMessage).onChange(async (v) => {
					s.commitMessage = v || DEFAULTS.commitMessage;
					await this.plugin.saveSettings();
				})
			);

		new Setting(containerEl)
			.setName("Auth")
			.setDesc(
				IN_FLATPAK
					? "Flatpak detected: git runs on the host via flatpak-spawn and authenticates with the gh credential helper."
					: "Git runs directly and authenticates with the gh credential helper."
			);
	}
}
