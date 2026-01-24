#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import https from 'node:https';
import os from 'node:os';
import { execSync } from 'node:child_process';
import { select, confirm } from '@inquirer/prompts';

const REPO = 'pdxxxx/gemini-mcp-rust';
const BINARY_NAME = process.platform === 'win32' ? 'gemini-mcp.exe' : 'gemini-mcp';

// Default installation paths
const INSTALL_DIR = process.platform === 'win32'
  ? path.join(process.env.LOCALAPPDATA || os.homedir(), 'Programs', 'gemini-mcp')
  : path.join(os.homedir(), '.local', 'bin');

const INSTALL_PATH = path.join(INSTALL_DIR, BINARY_NAME);

// Colored logging utilities
const log = {
  info: (msg) => console.log(`\x1b[36m[INFO]\x1b[0m ${msg}`),
  success: (msg) => console.log(`\x1b[32m[SUCCESS]\x1b[0m ${msg}`),
  warn: (msg) => console.log(`\x1b[33m[WARN]\x1b[0m ${msg}`),
  error: (msg) => console.log(`\x1b[31m[ERROR]\x1b[0m ${msg}`),
};

// Allowed hosts for download redirects (security)
const ALLOWED_DOWNLOAD_HOSTS = [
  'github.com',
  'objects.githubusercontent.com',
  'github-releases.githubusercontent.com'
];

// Platform detection and asset mapping
function getAssetDetails() {
  const arch = process.arch;
  const platform = process.platform;

  // Supported architectures
  const supportedArchs = ['x64', 'arm64'];
  if (!supportedArchs.includes(arch)) {
    throw new Error(`Unsupported architecture: ${arch}. Supported: x64, arm64`);
  }

  let assetKey = '';

  if (platform === 'win32') {
    // Windows ARM64 can run x64 binaries via emulation, and we don't build ARM64 Windows
    if (arch === 'arm64') {
      log.warn('Windows ARM64 detected. Using x64 binary (runs via emulation).');
    }
    assetKey = 'windows-amd64.exe';
  } else if (platform === 'darwin') {
    assetKey = arch === 'arm64' ? 'macos-arm64' : 'macos-amd64';
  } else if (platform === 'linux') {
    assetKey = arch === 'arm64' ? 'linux-arm64' : 'linux-amd64';
  } else {
    throw new Error(`Unsupported platform: ${platform}. Supported: win32, darwin, linux`);
  }

  return {
    name: `gemini-mcp-${assetKey}`,
    platform,
    arch
  };
}

// Fetch latest release from GitHub API
async function getLatestRelease() {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.github.com',
      path: `/repos/${REPO}/releases/latest`,
      headers: { 'User-Agent': 'gemini-mcp-installer' }
    };

    https.get(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          try {
            const release = JSON.parse(data);
            resolve(release);
          } catch (e) {
            reject(new Error('Failed to parse GitHub API response'));
          }
        } else if (res.statusCode === 404) {
          reject(new Error('No releases found. Please check the repository.'));
        } else if (res.statusCode === 403) {
          reject(new Error('GitHub API rate limit exceeded. Please try again later.'));
        } else {
          reject(new Error(`GitHub API returned status ${res.statusCode}`));
        }
      });
    }).on('error', (e) => reject(new Error(`Network error: ${e.message}`)));
  });
}

// Download file with redirect support and host validation
async function downloadFile(url, destPath) {
  return new Promise((resolve, reject) => {
    const request = (downloadUrl) => {
      // Validate URL host for security
      let urlObj;
      try {
        urlObj = new URL(downloadUrl);
      } catch {
        return reject(new Error(`Invalid URL: ${downloadUrl}`));
      }

      if (!ALLOWED_DOWNLOAD_HOSTS.includes(urlObj.hostname)) {
        return reject(new Error(`Download blocked: ${urlObj.hostname} is not in allowed hosts`));
      }

      if (urlObj.protocol !== 'https:') {
        return reject(new Error('Only HTTPS downloads are allowed'));
      }

      https.get(downloadUrl, (res) => {
        // Handle redirects (GitHub releases use redirects)
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          return request(res.headers.location);
        }

        if (res.statusCode !== 200) {
          return reject(new Error(`Download failed with status ${res.statusCode}`));
        }

        const totalSize = parseInt(res.headers['content-length'], 10);
        let downloadedSize = 0;

        const file = fs.createWriteStream(destPath);

        res.on('data', (chunk) => {
          downloadedSize += chunk.length;
          if (totalSize) {
            const percent = Math.round((downloadedSize / totalSize) * 100);
            process.stdout.write(`\r\x1b[36m[INFO]\x1b[0m Downloading... ${percent}%`);
          }
        });

        res.pipe(file);

        file.on('finish', () => {
          file.close();
          console.log(); // New line after progress
          resolve();
        });

        file.on('error', (err) => {
          fs.unlink(destPath, () => {});
          reject(err);
        });
      }).on('error', (e) => reject(new Error(`Download error: ${e.message}`)));
    };
    request(url);
  });
}

// Check if claude CLI is available
function isClaudeAvailable() {
  try {
    execSync('claude --version', { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

// Get installed version
function getInstalledVersion() {
  if (!fs.existsSync(INSTALL_PATH)) {
    return null;
  }
  try {
    const output = execSync(`"${INSTALL_PATH}" --version`, { encoding: 'utf-8' });
    const match = output.match(/(\d+\.\d+\.\d+)/);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

// Core actions
const Actions = {
  async install() {
    const assetDetails = getAssetDetails();
    log.info(`Detected platform: ${assetDetails.platform} (${assetDetails.arch})`);

    log.info('Fetching latest release...');
    const release = await getLatestRelease();
    const tag = release.tag_name;
    log.info(`Latest version: ${tag}`);

    // Find matching asset
    const asset = release.assets.find(a => a.name === assetDetails.name);
    if (!asset) {
      throw new Error(`No compatible binary found for ${assetDetails.name}. Available: ${release.assets.map(a => a.name).join(', ')}`);
    }

    // Create installation directory
    if (!fs.existsSync(INSTALL_DIR)) {
      log.info(`Creating directory: ${INSTALL_DIR}`);
      fs.mkdirSync(INSTALL_DIR, { recursive: true });
    }

    log.info(`Installing to: ${INSTALL_PATH}`);
    await downloadFile(asset.browser_download_url, INSTALL_PATH);

    // Set executable permissions on Unix-like systems
    if (process.platform !== 'win32') {
      fs.chmodSync(INSTALL_PATH, 0o755);
    }

    log.success(`Installed successfully: ${INSTALL_PATH}`);

    // PATH warning
    const pathEnv = process.env.PATH || '';
    if (!pathEnv.split(path.delimiter).includes(INSTALL_DIR)) {
      log.warn('Installation directory is not in your PATH.');
      if (process.platform === 'win32') {
        console.log(`  Add "${INSTALL_DIR}" to your user environment variables.`);
      } else {
        console.log(`  Add to your shell config (~/.zshrc or ~/.bashrc):`);
        console.log(`    export PATH="$PATH:${INSTALL_DIR}"`);
      }
    }

    return INSTALL_PATH;
  },

  async configure() {
    if (!fs.existsSync(INSTALL_PATH)) {
      log.error(`Binary not found at ${INSTALL_PATH}`);
      log.info('Please install first (option 1).');
      return;
    }

    if (!isClaudeAvailable()) {
      log.error('Claude CLI not found.');
      log.info('Install Claude Code first: https://docs.anthropic.com/en/docs/claude-code');
      return;
    }

    log.info('Configuring Claude Code...');
    try {
      // Remove existing config to avoid duplicates
      try {
        execSync('claude mcp remove gemini', { stdio: 'ignore' });
      } catch {
        // Ignore if not exists
      }

      execSync(`claude mcp add gemini "${INSTALL_PATH}"`, { stdio: 'inherit' });
      log.success('Gemini MCP has been configured for Claude Code!');
    } catch (e) {
      log.error(`Configuration failed: ${e.message}`);
      log.info(`You can manually run: claude mcp add gemini "${INSTALL_PATH}"`);
    }
  },

  async update() {
    const currentVersion = getInstalledVersion();

    if (!currentVersion) {
      log.warn('gemini-mcp is not installed.');
      const doInstall = await confirm({ message: 'Install now?', default: true });
      if (doInstall) {
        return Actions.install();
      }
      return;
    }

    log.info(`Current version: v${currentVersion}`);
    log.info('Checking for updates...');

    const release = await getLatestRelease();
    const latestVersion = release.tag_name.replace(/^v/, '');

    if (currentVersion === latestVersion) {
      log.success('Already on the latest version!');
      const reinstall = await confirm({ message: 'Reinstall anyway?', default: false });
      if (!reinstall) return;
    } else {
      log.info(`New version available: v${latestVersion}`);
      const doUpdate = await confirm({ message: `Update to v${latestVersion}?`, default: true });
      if (!doUpdate) return;
    }

    await Actions.install();
    log.success(`Updated to v${latestVersion}!`);
  },

  async uninstall() {
    let removed = false;

    if (fs.existsSync(INSTALL_PATH)) {
      const confirmDelete = await confirm({ message: `Delete ${INSTALL_PATH}?`, default: true });
      if (confirmDelete) {
        try {
          fs.unlinkSync(INSTALL_PATH);
          log.success('Binary removed.');
          removed = true;
        } catch (e) {
          log.error(`Failed to remove binary: ${e.message}`);
        }
      }
    } else {
      log.warn('Binary not found (already removed or not installed).');
    }

    if (isClaudeAvailable()) {
      const removeConfig = await confirm({ message: 'Remove from Claude configuration?', default: true });
      if (removeConfig) {
        try {
          execSync('claude mcp remove gemini', { stdio: 'inherit' });
          log.success('Claude configuration removed.');
          removed = true;
        } catch {
          log.warn('Could not remove from Claude config (may not exist).');
        }
      }
    }

    if (removed) {
      log.success('Uninstall complete!');
    }
  }
};

// Main menu
async function main() {
  console.log();
  console.log('\x1b[36m╔══════════════════════════════════════════╗\x1b[0m');
  console.log('\x1b[36m║       Gemini MCP Server Manager          ║\x1b[0m');
  console.log('\x1b[36m╚══════════════════════════════════════════╝\x1b[0m');
  console.log();

  // Show current status
  const installedVersion = getInstalledVersion();
  if (installedVersion) {
    log.info(`Installed version: v${installedVersion}`);
    log.info(`Location: ${INSTALL_PATH}`);
  } else {
    log.info('gemini-mcp is not installed.');
  }
  console.log();

  const choice = await select({
    message: 'What would you like to do?',
    choices: [
      {
        name: '1. Install gemini-mcp',
        value: 'install',
        description: 'Download and install the latest version'
      },
      {
        name: '2. Configure Claude Code',
        value: 'configure',
        description: 'Register gemini-mcp with Claude CLI'
      },
      {
        name: '3. Update gemini-mcp',
        value: 'update',
        description: 'Check for updates and upgrade'
      },
      {
        name: '4. Uninstall',
        value: 'uninstall',
        description: 'Remove binary and configuration'
      }
    ],
  });

  console.log();

  try {
    await Actions[choice]();
  } catch (error) {
    log.error(error.message);
    process.exit(1);
  }
}

main().catch((error) => {
  if (error.name === 'ExitPromptError') {
    // User pressed Ctrl+C
    console.log('\nCancelled.');
    process.exit(0);
  }
  log.error(error.message);
  process.exit(1);
});
