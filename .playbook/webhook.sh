#@ssh host=root.aiemotion.net

#@group "Install"

#@step "Add webhook repo as etckeeper submodule in /etc/webhook/repo"
WEBHOOK_REPO_URL="git@github.com:adnanh/webhook.git"
WEBHOOK_SUBMODULE_PATH="webhook/repo"
WEBHOOK_GITIGNORE_LINE_1="!webhook/"
WEBHOOK_GITIGNORE_LINE_2="!webhook/**"

if ! grep -Fxq "$WEBHOOK_GITIGNORE_LINE_1" /etc/.gitignore; then
  echo "$WEBHOOK_GITIGNORE_LINE_1" >>/etc/.gitignore
fi
if ! grep -Fxq "$WEBHOOK_GITIGNORE_LINE_2" /etc/.gitignore; then
  echo "$WEBHOOK_GITIGNORE_LINE_2" >>/etc/.gitignore
fi

mkdir -p /etc/webhook

if git -C /etc config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | grep -q " ${WEBHOOK_SUBMODULE_PATH}$"; then
  echo "Submodule path ${WEBHOOK_SUBMODULE_PATH} already configured in /etc/.gitmodules."
elif [ -d "/etc/${WEBHOOK_SUBMODULE_PATH}/.git" ] || [ -f "/etc/${WEBHOOK_SUBMODULE_PATH}/.git" ]; then
  echo "Existing git repo detected at /etc/${WEBHOOK_SUBMODULE_PATH}; skipping submodule add."
else
  git -C /etc submodule add "$WEBHOOK_REPO_URL" "$WEBHOOK_SUBMODULE_PATH"
  echo "Added submodule ${WEBHOOK_REPO_URL} at /etc/${WEBHOOK_SUBMODULE_PATH}"
fi

git -C /etc add .gitignore .gitmodules webhook

if ! git -C /etc diff --cached --quiet; then
  git -C /etc commit -m "Add webhook repo submodule"
else
  echo "No changes staged in /etc; nothing to commit or push."
fi

#@step "Build webhook image"
scs build webhook
