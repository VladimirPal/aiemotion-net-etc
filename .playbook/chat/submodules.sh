#@ssh host=root.aiemotion.net
#@env ETC_REPO_ROOT=/etc

#@group "Submodule catalog"
#@step "List chat submodules configured in .gitmodules"
. ".playbook/lib/submodules.sh"

echo "Repo root: ${ETC_REPO_ROOT}"
if ! has_chat_submodules; then
  echo "No chat submodules configured yet."
  exit 0
fi
list_chat_submodules

#@group "Add chat submodules"

#@step "Prepare .gitignore for chat submodules"
. ".playbook/lib/submodules.sh"

cmd_prepare_gitignore

#@step "Add chat submodules"
#@env CHAT_SUBMODULE_DEPTH=10
#@env CHAT_SUBMODULE_FULL=0
# Default depth 10, set CHAT_SUBMODULE_FULL=1 for full history
. ".playbook/lib/submodules.sh"

cmd_add_submodules

#@step "Commit chat submodule changes"
#@env CHAT_SUBMODULE_COMMIT_MESSAGE="Add chat submodules"
commit_message="${CHAT_SUBMODULE_COMMIT_MESSAGE:-Add chat submodules}"

echo "Committing staged submodule changes..."
if git -C "${ETC_REPO_ROOT}" diff --cached --quiet; then
  echo "No staged changes to commit."
  echo "Stage changes first (for example, run: Prepare .gitignore + Add chat submodules)."
  exit 0
fi

if git -C "${ETC_REPO_ROOT}" commit -m "${commit_message}"; then
  echo "Commit created."
  git -C "${ETC_REPO_ROOT}" --no-pager log -1 --oneline
else
  echo "Error: commit failed."
  exit 1
fi

#@group "Initialize chat submodules"

#@step "Initialize all chat submodules"
#@env CHAT_SUBMODULE_DEPTH=1
. ".playbook/lib/submodules.sh"

cmd_init

#@step "Initialize a specific chat submodule"
#@env CHAT_SUBMODULE_TARGET=element-web
#@env CHAT_SUBMODULE_DEPTH=1
. ".playbook/lib/submodules.sh"

cmd_init

#@group "Deinitialize chat submodules"

#@step "Deinitialize all chat submodules"
. ".playbook/lib/submodules.sh"

cmd_deinit

#@step "Deinitialize a specific chat submodule"
#@env CHAT_SUBMODULE_TARGET=synapse
. ".playbook/lib/submodules.sh"

cmd_deinit

#@group "Status"

#@step "Show status of chat submodules"
. ".playbook/lib/submodules.sh"

cmd_status

#@group "Updates"

#@step "Check for available updates"
#@env CHAT_SUBMODULE_BRIEF=0
# set CHAT_SUBMODULE_BRIEF=1 for summary
. ".playbook/lib/submodules.sh"

cmd_check_updates

#@step "Update all chat submodules to latest"
. ".playbook/lib/submodules.sh"

cmd_update

#@step "Update a specific chat submodule to latest"
#@env CHAT_SUBMODULE_TARGET=mas
. ".playbook/lib/submodules.sh"

cmd_update
