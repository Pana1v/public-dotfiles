const { Plugin, PluginSettingTab, Setting, Notice, requestUrl } = require("obsidian");
const { execFile, spawn } = require("child_process");

const GIT_PLUGIN_ID = "obsidian-git";
const GH_BINARIES = ["gh", "/app/bin/gh", "/usr/bin/gh"];
const GH_API_USER = "https://api.github.com/user";

function exec(bin, args, timeout = 15000) {
	return new Promise((resolve) => {
		execFile(bin, args, { timeout, encoding: "utf8" }, (err, stdout, stderr) => {
			resolve({ err, stdout: stdout || "", stderr: stderr || "" });
		});
	});
}

function execWithStdin(bin, args, input, timeout = 15000) {
	return new Promise((resolve) => {
		const child = spawn(bin, args, { stdio: ["pipe", "pipe", "pipe"] });
		let stdout = "";
		let stderr = "";
		const timer = setTimeout(() => child.kill("SIGKILL"), timeout);
		child.stdout.on("data", (d) => (stdout += d));
		child.stderr.on("data", (d) => (stderr += d));
		child.on("error", (err) => {
			clearTimeout(timer);
			resolve({ err, stdout, stderr });
		});
		child.on("close", (code) => {
			clearTimeout(timer);
			resolve({ err: code === 0 ? null : new Error(`exited with code ${code}`), stdout, stderr });
		});
		child.stdin.end(input);
	});
}

module.exports = class GitHubAuthPlugin extends Plugin {
	async onload() {
		this.settings = Object.assign(
			{ autoLink: true, ghPath: "" },
			await this.loadData()
		);
		this.ghBinary = null;

		this.addSettingTab(new GitHubAuthSettingTab(this));

		this.addCommand({
			id: "link",
			name: "Link gh CLI token to the Git plugin",
			callback: () => this.link(true),
		});
		this.addCommand({
			id: "status",
			name: "Show GitHub auth status",
			callback: () => this.showStatus(),
		});
		this.addCommand({
			id: "unlink",
			name: "Remove the GitHub token from the Git plugin",
			callback: () => this.unlink(),
		});

		this.statusBar = this.addStatusBarItem();
		this.statusBar.addClass("mod-right");

		this.app.workspace.onLayoutReady(() => {
			if (this.settings.autoLink) this.link(false);
			else this.renderStatus();
		});
	}

	onunload() {
		this.statusBar?.remove();
	}

	gitPlugin() {
		const plugins = this.app.plugins;
		if (!plugins) return null;
		return plugins.getPlugin?.(GIT_PLUGIN_ID) || plugins.plugins?.[GIT_PLUGIN_ID] || null;
	}

	async resolveGhBinary() {
		if (this.ghBinary) return this.ghBinary;
		const candidates = this.settings.ghPath
			? [this.settings.ghPath]
			: GH_BINARIES;
		for (const bin of candidates) {
			const res = await exec(bin, ["--version"]);
			if (!res.err) {
				this.ghBinary = bin;
				return bin;
			}
		}
		return null;
	}

	async fetchToken(bin) {
		const direct = await exec(bin, ["auth", "token"]);
		if (!direct.err && direct.stdout.trim()) {
			return { token: direct.stdout.trim(), username: "" };
		}

		const helper = await execWithStdin(
			bin,
			["auth", "git-credential", "get"],
			"protocol=https\nhost=github.com\n\n"
		);
		if (!helper.err) {
			const token = /^password=(.*)$/m.exec(helper.stdout)?.[1]?.trim();
			const username = /^username=(.*)$/m.exec(helper.stdout)?.[1]?.trim();
			if (token) return { token, username: username || "" };
		}
		return null;
	}

	async resolveLogin(token) {
		try {
			const res = await requestUrl({
				url: GH_API_USER,
				headers: {
					Authorization: `Bearer ${token}`,
					Accept: "application/vnd.github+json",
					"User-Agent": "obsidian-git-gh-auth",
				},
				throw: false,
			});
			if (res.status >= 200 && res.status < 300) {
				return res.json?.login || "";
			}
		} catch (e) {
			// fall through to the placeholder username
		}
		return "";
	}

	storeCredentials(git, username, token) {
		const store = git.localStorage;
		if (store?.setUsername && store?.setPassword) {
			store.setUsername(username);
			store.setPassword(token);
			return true;
		}
		const prefix = `${git.manifest?.id || GIT_PLUGIN_ID}:`;
		if (this.app.saveLocalStorage) {
			this.app.saveLocalStorage(`${prefix}username`, username);
			this.app.saveLocalStorage(`${prefix}password`, token);
			return true;
		}
		return false;
	}

	async link(notify) {
		const git = this.gitPlugin();
		if (!git) {
			if (notify) new Notice("GitHub Auth: the Git plugin is not installed or not enabled.");
			this.renderStatus();
			return false;
		}

		const bin = await this.resolveGhBinary();
		if (!bin) {
			if (notify) new Notice("GitHub Auth: no gh CLI found.");
			this.renderStatus();
			return false;
		}

		const creds = await this.fetchToken(bin);
		if (!creds) {
			if (notify) new Notice("GitHub Auth: gh has no token for github.com.");
			this.renderStatus();
			return false;
		}

		const username = creds.username || (await this.resolveLogin(creds.token)) || "x-access-token";
		if (!this.storeCredentials(git, username, creds.token)) {
			if (notify) new Notice("GitHub Auth: could not write credentials for the Git plugin.");
			this.renderStatus();
			return false;
		}

		if (notify) new Notice(`GitHub Auth: linked the Git plugin as ${username}.`);
		this.renderStatus();
		return true;
	}

	unlink() {
		const git = this.gitPlugin();
		if (!git) {
			new Notice("GitHub Auth: the Git plugin is not installed or not enabled.");
			return;
		}
		const store = git.localStorage;
		if (store?.setUsername && store?.setPassword) {
			store.setUsername("");
			store.setPassword("");
		} else if (this.app.saveLocalStorage) {
			const prefix = `${git.manifest?.id || GIT_PLUGIN_ID}:`;
			this.app.saveLocalStorage(`${prefix}username`, "");
			this.app.saveLocalStorage(`${prefix}password`, "");
		}
		new Notice("GitHub Auth: token removed from the Git plugin.");
		this.renderStatus();
	}

	storedUsername() {
		const git = this.gitPlugin();
		if (!git) return "";
		const store = git.localStorage;
		if (store?.getUsername) return store.getUsername() || "";
		const prefix = `${git.manifest?.id || GIT_PLUGIN_ID}:`;
		return this.app.loadLocalStorage?.(`${prefix}username`) || "";
	}

	async showStatus() {
		const git = this.gitPlugin();
		if (!git) {
			new Notice("GitHub Auth: the Git plugin is not installed or not enabled.");
			return;
		}
		const username = this.storedUsername();
		const bin = await this.resolveGhBinary();
		if (!username) {
			new Notice(
				bin
					? "GitHub Auth: the Git plugin has no token yet. Run 'Link gh CLI token to the Git plugin'."
					: "GitHub Auth: the Git plugin has no token and no gh CLI was found."
			);
			return;
		}
		new Notice(`GitHub Auth: the Git plugin is linked as ${username}.`);
	}

	renderStatus() {
		if (!this.statusBar) return;
		const linked = !!this.storedUsername();
		this.statusBar.setText(linked ? "GH: linked" : "GH: none");
		this.statusBar.title = linked
			? "GitHub Auth: the Git plugin has a token"
			: "GitHub Auth: the Git plugin has no token";
	}

	async saveSettings() {
		await this.saveData(this.settings);
	}
};

class GitHubAuthSettingTab extends PluginSettingTab {
	constructor(plugin) {
		super(plugin.app, plugin);
		this.plugin = plugin;
	}

	display() {
		const { containerEl } = this;
		containerEl.empty();

		new Setting(containerEl)
			.setName("Link on startup")
			.setDesc("Read the gh CLI token and hand it to the Git plugin whenever Obsidian starts.")
			.addToggle((toggle) =>
				toggle.setValue(this.plugin.settings.autoLink).onChange(async (value) => {
					this.plugin.settings.autoLink = value;
					await this.plugin.saveSettings();
				})
			);

		new Setting(containerEl)
			.setName("gh CLI path")
			.setDesc("Leave empty to search the PATH and the usual install locations.")
			.addText((text) =>
				text.setPlaceholder("gh").setValue(this.plugin.settings.ghPath).onChange(async (value) => {
					this.plugin.settings.ghPath = value.trim();
					this.plugin.ghBinary = null;
					await this.plugin.saveSettings();
				})
			);

		new Setting(containerEl)
			.setName("Link now")
			.setDesc("Copy the current gh CLI token into the Git plugin.")
			.addButton((button) =>
				button.setButtonText("Link").onClick(async () => {
					await this.plugin.link(true);
					this.display();
				})
			);

		new Setting(containerEl)
			.setName("Remove token")
			.setDesc("Clear the token the Git plugin holds.")
			.addButton((button) =>
				button.setButtonText("Remove").onClick(async () => {
					this.plugin.unlink();
					this.display();
				})
			);
	}
}
