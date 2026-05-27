#!/usr/bin/env python3
import os
import subprocess
import sys
import urllib.parse
import urllib.request
import json
import re
from datetime import datetime

# Configuration
REPO_OWNER = "Mudit01100001"
REPO_NAME = "claude-usage-menu-bar"
CHANGELOG_PATH = "CHANGELOG.md"

def run_command(cmd, shell=False):
    """Helper to run a shell command and return output."""
    try:
        result = subprocess.run(
            cmd,
            shell=shell,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
        print(f"Stderr: {e.stderr}")
        return None

def get_tags():
    """Retrieve list of git tags sorted by creation date."""
    tags_str = run_command(["git", "tag", "--sort=-creatordate"])
    if not tags_str:
        return []
    return tags_str.split("\n")

def get_commits_since(tag=None):
    """Retrieve commits since the specified tag, or all commits if none."""
    if tag:
        cmd = ["git", "log", f"{tag}..HEAD", "--oneline"]
    else:
        cmd = ["git", "log", "--oneline"]
    
    commits_str = run_command(cmd)
    if not commits_str:
        return []
    return commits_str.split("\n")

def parse_version(tag):
    """Extract major, minor, patch numbers from tag string (e.g., v1.1.0)."""
    match = re.match(r"^v?(\d+)\.(\d+)\.(\d+)$", tag)
    if match:
        return list(map(int, match.groups()))
    return [0, 0, 0]

def suggest_next_version(latest_tag):
    """Suggest next patch and minor versions based on the latest tag."""
    if not latest_tag:
        return "v1.0.0", "v1.0.0"
    major, minor, patch = parse_version(latest_tag)
    patch_version = f"v{major}.{minor}.{patch + 1}"
    minor_version = f"v{major}.{minor + 1}.0"
    return patch_version, minor_version

def categorize_commits(commits):
    """Group commit messages based on conventional commit prefixes."""
    categories = {
        "features": [],
        "fixes": [],
        "refactor": [],
        "polish": []
    }
    
    for commit in commits:
        # Strip commit hash
        parts = commit.split(" ", 1)
        if len(parts) < 2:
            continue
        msg = parts[1]
        
        lower_msg = msg.lower()
        if any(lower_msg.startswith(prefix) for prefix in ["feat:", "feature:", "add:"]):
            categories["features"].append(msg)
        elif any(lower_msg.startswith(prefix) for prefix in ["fix:", "bug:", "resolve:", "hotfix:"]):
            categories["fixes"].append(msg)
        elif any(lower_msg.startswith(prefix) for prefix in ["refactor:", "perf:", "performance:"]):
            categories["refactor"].append(msg)
        elif any(lower_msg.startswith(prefix) for prefix in ["docs:", "chore:", "style:", "clean:", "cleanup:"]):
            categories["polish"].append(msg)
        else:
            # Default fallback category
            categories["polish"].append(msg)
            
    return categories

def generate_release_notes(version, date_str, categories):
    """Generate a polished markdown release notes body."""
    body = f"# Claude Usage macOS App {version} 🚀\n\n"
    body += f"Released on {date_str}. This release brings updates and stability enhancements to the Claude usage tracker.\n\n"
    body += "---\n\n"
    
    has_changes = False
    
    if categories["features"]:
        body += "## 🚀 New Features\n"
        for item in categories["features"]:
            # Strip prefixes for cleanliness
            clean_item = re.sub(r'^(feat|feature|add):\s*', '', item, flags=re.IGNORECASE)
            body += f"* **Feature:** {clean_item.capitalize()}\n"
        body += "\n"
        has_changes = True
        
    if categories["fixes"]:
        body += "## 🐛 Bug Fixes\n"
        for item in categories["fixes"]:
            clean_item = re.sub(r'^(fix|bug|resolve|hotfix):\s*', '', item, flags=re.IGNORECASE)
            body += f"* **Fix:** {clean_item.capitalize()}\n"
        body += "\n"
        has_changes = True
        
    if categories["refactor"]:
        body += "## ⚡ Performance & Refactoring\n"
        for item in categories["refactor"]:
            clean_item = re.sub(r'^(refactor|perf|performance):\s*', '', item, flags=re.IGNORECASE)
            body += f"* {clean_item.capitalize()}\n"
        body += "\n"
        has_changes = True
        
    if categories["polish"] or not has_changes:
        body += "## 🧹 Documentation & Polish\n"
        items = categories["polish"] if categories["polish"] else ["General updates and maintenance."]
        for item in items:
            clean_item = re.sub(r'^(docs|chore|style|clean|cleanup):\s*', '', item, flags=re.IGNORECASE)
            body += f"* {clean_item.capitalize()}\n"
        body += "\n"
        
    body += "---\n\n"
    body += "## 📦 Installation & Verification\n"
    body += "```bash\n"
    body += "./build.sh\n"
    body += "open ClaudeUsage.app\n"
    body += "```\n"
    body += "To verify the widget registration status:\n"
    body += "```bash\n"
    body += "pluginkit -m -v | grep -i ClaudeUsage\n"
    body += "```\n"
    
    return body

def update_changelog(version, date_str, categories):
    """Prepend the new release notes to the CHANGELOG.md file."""
    # Format changelog entry
    entry = f"## [{version.lstrip('v')}] - {date_str}\n\n"
    
    if categories["features"]:
        entry += "### Added\n"
        for item in categories["features"]:
            clean_item = re.sub(r'^(feat|feature|add):\s*', '', item, flags=re.IGNORECASE)
            entry += f"- {clean_item.capitalize()}\n"
        entry += "\n"
        
    if categories["fixes"]:
        entry += "### Fixed\n"
        for item in categories["fixes"]:
            clean_item = re.sub(r'^(fix|bug|resolve|hotfix):\s*', '', item, flags=re.IGNORECASE)
            entry += f"- {clean_item.capitalize()}\n"
        entry += "\n"
        
    if categories["refactor"] or categories["polish"]:
        entry += "### Changed\n"
        items = categories["refactor"] + categories["polish"]
        for item in items:
            clean_item = re.sub(r'^(refactor|perf|performance|docs|chore|style|clean|cleanup):\s*', '', item, flags=re.IGNORECASE)
            entry += f"- {clean_item.capitalize()}\n"
        entry += "\n"
        
    # Read existing changelog content
    old_content = ""
    if os.path.exists(CHANGELOG_PATH):
        with open(CHANGELOG_PATH, "r") as f:
            old_content = f.read()
            
    # Insert new entry after title/headers
    new_content = ""
    changelog_header_match = re.search(r"^(# Changelog\n\nAll notable changes.*?\n\n---\n\n)", old_content, re.DOTALL)
    
    if changelog_header_match:
        header = changelog_header_match.group(1)
        body = old_content[len(header):]
        new_content = header + entry + "---\n\n" + body
    else:
        # Fallback if CHANGELOG.md doesn't match standard template
        if old_content.startswith("# Changelog"):
            lines = old_content.split("\n")
            new_content = lines[0] + "\n\n" + entry + "---\n\n" + "\n".join(lines[1:])
        else:
            new_content = "# Changelog\n\n" + entry + "---\n\n" + old_content
            
    with open(CHANGELOG_PATH, "w") as f:
        f.write(new_content)
        
    print(f"Updated {CHANGELOG_PATH} successfully.")

def publish_github_release(tag, title, body):
    """Attempt to publish the release via the GitHub API if a token is present."""
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        # Fallback to browser URL-encoded redirection
        print("GITHUB_TOKEN environment variable not set. Opening browser for manual creation...")
        body_encoded = urllib.parse.quote(body)
        title_encoded = urllib.parse.quote(title)
        url = f"https://github.com/{REPO_OWNER}/{REPO_NAME}/releases/new?tag={tag}&title={title_encoded}&body={body_encoded}"
        
        # Open in browser
        try:
            import webbrowser
            webbrowser.open(url)
            print(f"Opened new release tab in browser.")
        except Exception:
            print(f"Could not open browser. Please navigate to:\n{url}")
        return False

    # Call GitHub API
    api_url = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/releases"
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "Claude-Usage-Releaser"
    }
    data = {
        "tag_name": tag,
        "name": title,
        "body": body,
        "draft": False,
        "prerelease": False
    }
    
    req = urllib.request.Request(
        api_url,
        data=json.dumps(data).encode("utf-8"),
        headers=headers,
        method="POST"
    )
    
    try:
        with urllib.request.urlopen(req) as response:
            res_data = json.loads(response.read().decode("utf-8"))
            print(f"🎉 Successfully published release {tag} on GitHub!")
            print(f"Release URL: {res_data.get('html_url')}")
            return True
    except urllib.error.HTTPError as e:
        print(f"Failed to publish release via API (HTTP {e.code})")
        print(f"Response: {e.read().decode('utf-8')}")
        return False
    except Exception as e:
        print(f"Failed to publish release via API: {e}")
        return False

def main():
    print("=== Claude Usage macOS Release Automation ===")
    
    # 1. Fetch tags and commits
    tags = get_tags()
    latest_tag = tags[0] if tags else None
    print(f"Latest git tag found: {latest_tag if latest_tag else 'None'}")
    
    commits = get_commits_since(latest_tag)
    print(f"Found {len(commits)} commits since last release.")
    
    # 2. Suggest version
    suggested_patch, suggested_minor = suggest_next_version(latest_tag)
    print(f"Suggested next version:")
    print(f"  1) {suggested_patch} (Patch release)")
    print(f"  2) {suggested_minor} (Minor feature release)")
    
    choice = input("Enter choice (1 or 2) or type a custom tag (e.g. v1.2.0) [1]: ").strip()
    if choice == "2":
        tag = suggested_minor
    elif choice == "1" or choice == "":
        tag = suggested_patch
    else:
        tag = choice
        if not tag.startswith("v"):
            tag = "v" + tag
            
    title_default = f"{tag} - Release Notes"
    title = input(f"Enter release title [{title_default}]: ").strip()
    if not title:
        title = title_default
        
    # 3. Categorize and build release notes
    categories = categorize_commits(commits)
    date_str = datetime.now().strftime("%Y-%m-%d")
    
    body = generate_release_notes(tag, date_str, categories)
    
    print("\n--- Drafted Release Notes ---")
    print(body)
    print("-----------------------------\n")
    
    confirm = input("Do you want to proceed with this release? (y/n) [y]: ").strip().lower()
    if confirm == "n":
        print("Release aborted.")
        sys.exit(0)
        
    # 4. Update CHANGELOG.md locally
    update_changelog(tag, date_str, categories)
    
    # 5. Git Commit and Tagging
    print("Staging and committing CHANGELOG.md...")
    run_command(["git", "add", CHANGELOG_PATH])
    run_command(["git", "commit", "-m", f"chore: update CHANGELOG.md for release {tag}"])
    
    current_branch = run_command(["git", "branch", "--show-current"])
    print(f"Pushing commits to origin/{current_branch}...")
    run_command(["git", "push", "origin", current_branch])
    
    print(f"Creating local tag {tag}...")
    run_command(["git", "tag", tag])
    print(f"Pushing tag {tag} to origin...")
    run_command(["git", "push", "origin", tag])
    
    # 6. Publish on GitHub
    publish_github_release(tag, title, body)
    
if __name__ == "__main__":
    main()
