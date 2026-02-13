#@ssh host=root.aiemotion.net

#@group "Install"

#@step "Generate dedicated SSH key for memory-alive-docs submodule"
#@env DOCS_DEPLOY_KEY_PATH=/root/.ssh/memory_alive_docs_rsa
#@env DOCS_DEPLOY_KEY_COMMENT=memory-alive-docs-deploy
mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ ! -f "${DOCS_DEPLOY_KEY_PATH}" ]; then
  ssh-keygen -t rsa -b 4096 -C "${DOCS_DEPLOY_KEY_COMMENT}" -N "" -f "${DOCS_DEPLOY_KEY_PATH}"
  echo "Created SSH key: ${DOCS_DEPLOY_KEY_PATH}"
else
  echo "SSH key already exists: ${DOCS_DEPLOY_KEY_PATH}"
fi

chmod 600 "${DOCS_DEPLOY_KEY_PATH}"
chmod 644 "${DOCS_DEPLOY_KEY_PATH}.pub"

#@step "Print public key to add as GitHub deploy key (read-only)"
#@env DOCS_DEPLOY_KEY_PATH=/root/.ssh/memory_alive_docs_rsa
echo "Add this public key to GitHub repo VladimirPal/memory-alive-docs as a deploy key:"
cat "${DOCS_DEPLOY_KEY_PATH}.pub"

#@step "Ensure GitHub host key is present in known_hosts"
if [ ! -f /root/.ssh/known_hosts ] || ! ssh-keygen -F github.com -f /root/.ssh/known_hosts >/dev/null 2>&1; then
  ssh-keyscan -H github.com >>/root/.ssh/known_hosts
  echo "Added github.com host key to /root/.ssh/known_hosts"
else
  echo "github.com host key already present in /root/.ssh/known_hosts"
fi
chmod 644 /root/.ssh/known_hosts

#@step "Ensure dedicated SSH host alias for memory-alive-docs exists"
#@env DOCS_SUBMODULES_SSH_CONFIG=/etc/ssh/submodules_config
#@env DOCS_SSH_HOST_ALIAS=github-memory-alive-docs
#@env DOCS_DEPLOY_KEY_PATH=/root/.ssh/memory_alive_docs_rsa
mkdir -p /etc/ssh
touch "${DOCS_SUBMODULES_SSH_CONFIG}"

if grep -Fxq "Host ${DOCS_SSH_HOST_ALIAS}" "${DOCS_SUBMODULES_SSH_CONFIG}"; then
  echo "Host alias ${DOCS_SSH_HOST_ALIAS} already exists in ${DOCS_SUBMODULES_SSH_CONFIG}"
else
  cat >>"${DOCS_SUBMODULES_SSH_CONFIG}" <<EOF
Host ${DOCS_SSH_HOST_ALIAS}
    HostName github.com
    User git
    IdentityFile ${DOCS_DEPLOY_KEY_PATH}
    IdentitiesOnly yes
EOF
  echo "Added host alias ${DOCS_SSH_HOST_ALIAS} to ${DOCS_SUBMODULES_SSH_CONFIG}"
fi

chmod 600 "${DOCS_SUBMODULES_SSH_CONFIG}"

#@step "Add memory-alive-docs repo as etckeeper submodule in /etc/control/docs/memory-alive-docs"
#@env DOCS_REPO_URL=git@github-memory-alive-docs:VladimirPal/memory-alive-docs.git
#@env DOCS_SUBMODULE_PATH=control/docs/memory-alive-docs
#@env DOCS_GITIGNORE_LINE_1=!control/docs/
#@env DOCS_GITIGNORE_LINE_2=!control/docs/**
#@env DOCS_GITIGNORE_LINE_3=!control/docs/memory-alive-docs/
#@env DOCS_GITIGNORE_LINE_4=!control/docs/memory-alive-docs/**
if ! grep -Fxq "$DOCS_GITIGNORE_LINE_1" /etc/.gitignore; then
  echo "$DOCS_GITIGNORE_LINE_1" >>/etc/.gitignore
fi
if ! grep -Fxq "$DOCS_GITIGNORE_LINE_2" /etc/.gitignore; then
  echo "$DOCS_GITIGNORE_LINE_2" >>/etc/.gitignore
fi
if ! grep -Fxq "$DOCS_GITIGNORE_LINE_3" /etc/.gitignore; then
  echo "$DOCS_GITIGNORE_LINE_3" >>/etc/.gitignore
fi
if ! grep -Fxq "$DOCS_GITIGNORE_LINE_4" /etc/.gitignore; then
  echo "$DOCS_GITIGNORE_LINE_4" >>/etc/.gitignore
fi

mkdir -p /etc/control/docs

if git -C /etc config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | grep -q " ${DOCS_SUBMODULE_PATH}$"; then
  echo "Submodule path ${DOCS_SUBMODULE_PATH} already configured in /etc/.gitmodules."
elif [ -d "/etc/${DOCS_SUBMODULE_PATH}/.git" ] || [ -f "/etc/${DOCS_SUBMODULE_PATH}/.git" ]; then
  echo "Existing git repo detected at /etc/${DOCS_SUBMODULE_PATH}; skipping submodule add."
else
  git -C /etc submodule add "${DOCS_REPO_URL}" "${DOCS_SUBMODULE_PATH}"
  echo "Added submodule ${DOCS_REPO_URL} at /etc/${DOCS_SUBMODULE_PATH}"
fi

git -C /etc add .gitignore .gitmodules ssh/submodules_config control/docs/memory-alive-docs

if ! git -C /etc diff --cached --quiet; then
  git -C /etc commit -m "Add memory-alive-docs submodule"
else
  echo "No changes staged in /etc; nothing to commit or push."
fi
