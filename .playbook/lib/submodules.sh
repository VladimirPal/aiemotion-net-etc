#!/usr/bin/env bash

. ".playbook/lib/base.sh"

ETC_REPO_ROOT="${ETC_REPO_ROOT:-$(git -C /etc rev-parse --show-toplevel 2>/dev/null || echo "/etc")}"
ETC_GITMODULES_FILE="${ETC_GITMODULES_FILE:-${ETC_REPO_ROOT}/.gitmodules}"

CHAT_COLOR_RED="$(printf '\033[0;31m')"
CHAT_COLOR_GREEN="$(printf '\033[0;32m')"
CHAT_COLOR_YELLOW="$(printf '\033[1;33m')"
CHAT_COLOR_BLUE="$(printf '\033[0;34m')"
CHAT_COLOR_RESET="$(printf '\033[0m')"

get_chat_submodules() {
  if [ ! -f "${ETC_GITMODULES_FILE}" ]; then
    return 0
  fi

  git config --file "${ETC_GITMODULES_FILE}" --get-regexp '^submodule\..*\.path' 2>/dev/null | while read -r key module_path; do
    if [[ "${module_path}" == chat/* ]]; then
      name="${key#submodule.}"
      name="${name%.path}"
      echo "${name}|${module_path}"
    fi
  done
}

list_chat_submodules() {
  while IFS='|' read -r name module_path; do
    display_name="${name}"
    if [[ "${display_name}" == "${module_path}" ]]; then
      display_name="${module_path#chat/}"
      display_name="${display_name%/repo}"
    fi
    printf '%s -> %s\n' "${display_name}" "${module_path}"
  done < <(get_chat_submodules)
}

get_submodule_info() {
  local name="$1"
  local module_path="$2"
  local branch
  branch=$(git config --file "${ETC_GITMODULES_FILE}" --get "submodule.${name}.branch" 2>/dev/null || echo "main")
  local url
  url=$(git config --file "${ETC_GITMODULES_FILE}" --get "submodule.${name}.url" 2>/dev/null || echo "")
  echo "${name}|${module_path}|${branch}|${url}"
}

has_chat_submodules() {
  local count
  count="$(get_chat_submodules | wc -l | tr -d ' ')"
  [ "${count:-0}" -gt 0 ]
}

cmd_prepare_gitignore() {
  local gitignore_file="${ETC_REPO_ROOT}/.gitignore"
  echo -e "${CHAT_COLOR_BLUE}Preparing .gitignore for chat submodules...${CHAT_COLOR_RESET}"

  touch "${gitignore_file}"

  local changed=false

  local desired_rules=(
    "!chat/"
    "!chat/**"
    "chat/synapse/media_store"
    "chat/postgresql/postgres_data"
    "chat/*/backups"
    "chat/mautrix-telegram/*.db"
    "chat/mautrix-telegram/*.db-shm"
    "chat/mautrix-telegram/*.db-wal"
  )

  local rule
  for rule in "${desired_rules[@]}"; do
    if ! grep -Fxq "${rule}" "${gitignore_file}"; then
      printf '%s\n' "${rule}" >>"${gitignore_file}"
      changed=true
    fi
  done

  if [ "${changed}" = true ]; then
    git -C "${ETC_REPO_ROOT}" add ".gitignore" 2>/dev/null || true
    echo -e "${CHAT_COLOR_GREEN}Updated ${gitignore_file}${CHAT_COLOR_RESET}"
  else
    echo -e "${CHAT_COLOR_GREEN}No .gitignore changes needed${CHAT_COLOR_RESET}"
  fi
}

cmd_add_submodules() {
  local depth="${CHAT_SUBMODULE_DEPTH:-1}"
  if [ "${CHAT_SUBMODULE_FULL:-0}" = "1" ]; then
    depth="0"
  fi

  echo -e "${CHAT_COLOR_BLUE}Adding chat submodules...${CHAT_COLOR_RESET}"

  # name|path|branch|url
  local modules=(
    "synapse|chat/synapse/repo|develop|https://github.com/element-hq/synapse.git"
    "synapse-s3provider|chat/synapse/s3provider/repo|main|git@github.com:matrix-org/synapse-s3-storage-provider.git"
    "mas|chat/mas/repo|main|https://github.com/element-hq/matrix-authentication-service.git"
    "element-web|chat/element-web/repo|develop|https://github.com/element-hq/element-web.git"
  )

  local added_any=false
  local -a added_modules=()
  local -a already_present_modules=()
  local -a repaired_modules=()

  for entry in "${modules[@]}"; do
    IFS='|' read -r name module_path branch url <<<"${entry}"

    if git -C "${ETC_REPO_ROOT}" ls-files --error-unmatch "${module_path}" >/dev/null 2>&1; then
      if git config --file "${ETC_GITMODULES_FILE}" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}' | grep -Fxq "${module_path}"; then
        echo -e "${CHAT_COLOR_GREEN}✓ Already present: ${name} (${module_path})${CHAT_COLOR_RESET}"
        already_present_modules+=("${name}")
        continue
      fi

      echo -e "${CHAT_COLOR_YELLOW}⚠️  ${module_path} is already in the git index but not recorded in .gitmodules. Repairing .gitmodules entry for ${name}...${CHAT_COLOR_RESET}"
      git config --file "${ETC_GITMODULES_FILE}" "submodule.${name}.path" "${module_path}"
      git config --file "${ETC_GITMODULES_FILE}" "submodule.${name}.url" "${url}"
      git config --file "${ETC_GITMODULES_FILE}" "submodule.${name}.branch" "${branch}"
      git -C "${ETC_REPO_ROOT}" add "${ETC_GITMODULES_FILE}"
      added_any=true
      repaired_modules+=("${name}")
      continue
    fi

    if git config --file "${ETC_GITMODULES_FILE}" --get "submodule.${name}.path" >/dev/null 2>&1; then
      echo -e "${CHAT_COLOR_GREEN}✓ Already present: ${name} (${module_path})${CHAT_COLOR_RESET}"
      already_present_modules+=("${name}")
      continue
    fi

    if [ -e "${ETC_REPO_ROOT}/${module_path}" ] && [ ! -d "${ETC_REPO_ROOT}/${module_path}/.git" ] && [ ! -f "${ETC_REPO_ROOT}/${module_path}/.git" ]; then
      echo -e "${CHAT_COLOR_RED}Error: Path exists but is not a git submodule: ${module_path}${CHAT_COLOR_RESET}"
      echo -e "${CHAT_COLOR_YELLOW}Move it aside or delete it, then re-run this step.${CHAT_COLOR_RESET}"
      exit 1
    fi

    if [ "${depth}" != "0" ]; then
      echo -e "${CHAT_COLOR_BLUE}Adding ${name} (${module_path}) from ${url} (branch: ${branch}, depth: ${depth})...${CHAT_COLOR_RESET}"
      if ! git -C "${ETC_REPO_ROOT}" submodule add -f --depth "${depth}" -b "${branch}" "${url}" "${module_path}"; then
        echo -e "${CHAT_COLOR_YELLOW}Warning: 'git submodule add --depth' failed. Retrying without --depth...${CHAT_COLOR_RESET}"
        if ! git -C "${ETC_REPO_ROOT}" submodule add -f -b "${branch}" "${url}" "${module_path}"; then
          echo -e "${CHAT_COLOR_RED}Error: Failed to add submodule ${name} (${module_path}).${CHAT_COLOR_RESET}"
          exit 1
        fi
      fi
    else
      echo -e "${CHAT_COLOR_BLUE}Adding ${name} (${module_path}) from ${url} (branch: ${branch})...${CHAT_COLOR_RESET}"
      if ! git -C "${ETC_REPO_ROOT}" submodule add -f -b "${branch}" "${url}" "${module_path}"; then
        echo -e "${CHAT_COLOR_RED}Error: Failed to add submodule ${name} (${module_path}).${CHAT_COLOR_RESET}"
        exit 1
      fi
    fi
    git config --file "${ETC_GITMODULES_FILE}" "submodule.${name}.branch" "${branch}"
    git -C "${ETC_REPO_ROOT}" add "${ETC_GITMODULES_FILE}"
    added_any=true
    echo -e "${CHAT_COLOR_GREEN}✓ Added ${name}${CHAT_COLOR_RESET}"
    added_modules+=("${name}")
  done

  echo ""
  if [ "${added_any}" = true ]; then
    if [ "${#added_modules[@]}" -gt 0 ]; then
      echo -e "${CHAT_COLOR_GREEN}Added:${CHAT_COLOR_RESET} ${added_modules[*]}"
    fi
    if [ "${#repaired_modules[@]}" -gt 0 ]; then
      echo -e "${CHAT_COLOR_YELLOW}Recorded in .gitmodules (already in index):${CHAT_COLOR_RESET} ${repaired_modules[*]}"
    fi
    if [ "${#already_present_modules[@]}" -gt 0 ]; then
      echo -e "${CHAT_COLOR_GREEN}Already present (nothing to add):${CHAT_COLOR_RESET} ${already_present_modules[*]}"
    fi
    echo -e "${CHAT_COLOR_GREEN}Done. Submodules were added and staged. Commit the changes to persist them.${CHAT_COLOR_RESET}"
    echo "  git status"
    echo '  git commit -m "Add chat submodules"'
  else
    if [ "${#already_present_modules[@]}" -gt 0 ]; then
      echo -e "${CHAT_COLOR_GREEN}Already present (nothing to add):${CHAT_COLOR_RESET} ${already_present_modules[*]}"
    fi
    echo -e "${CHAT_COLOR_GREEN}Nothing to add. All chat submodules are already configured.${CHAT_COLOR_RESET}"
  fi
}

cmd_init() {
  local specific_module="${CHAT_SUBMODULE_TARGET-}"
  local depth="${CHAT_SUBMODULE_DEPTH:-1}"

  echo -e "${CHAT_COLOR_BLUE}Initializing chat submodules...${CHAT_COLOR_RESET}"

  if ! has_chat_submodules; then
    echo -e "${CHAT_COLOR_YELLOW}No chat submodules are configured in .gitmodules yet.${CHAT_COLOR_RESET}"
    echo -e "${CHAT_COLOR_YELLOW}Run the add-submodules step first.${CHAT_COLOR_RESET}"
    exit 1
  fi

  if [ -n "${specific_module}" ]; then
    local found=false
    while IFS='|' read -r name module_path; do
      if [[ ${name} == "${specific_module}" ]] || [[ ${module_path} == "${specific_module}" ]] || [[ ${module_path} == *"${specific_module}"* ]]; then
        found=true
        echo -e "${CHAT_COLOR_BLUE}Initializing ${name} (${module_path})...${CHAT_COLOR_RESET}"
        if [ "${depth}" != "0" ]; then
          if ! git -C "${ETC_REPO_ROOT}" submodule update --init --recursive --depth "${depth}" "${module_path}"; then
            echo -e "${CHAT_COLOR_YELLOW}Warning: 'git submodule update --depth' failed. Retrying without --depth...${CHAT_COLOR_RESET}"
            git -C "${ETC_REPO_ROOT}" submodule update --init --recursive "${module_path}"
          fi
        else
          git -C "${ETC_REPO_ROOT}" submodule update --init --recursive "${module_path}"
        fi
        echo -e "${CHAT_COLOR_GREEN}✓ Initialized ${name}${CHAT_COLOR_RESET}"
        break
      fi
    done < <(get_chat_submodules)

    if [ "${found}" = false ]; then
      echo -e "${CHAT_COLOR_RED}Error: Submodule '${specific_module}' not found${CHAT_COLOR_RESET}"
      exit 1
    fi
  else
    while IFS='|' read -r name module_path; do
      echo -e "${CHAT_COLOR_BLUE}Initializing ${name} (${module_path})...${CHAT_COLOR_RESET}"
      if [ "${depth}" != "0" ]; then
        if ! git -C "${ETC_REPO_ROOT}" submodule update --init --recursive --depth "${depth}" "${module_path}"; then
          echo -e "${CHAT_COLOR_YELLOW}Warning: 'git submodule update --depth' failed. Retrying without --depth...${CHAT_COLOR_RESET}"
          git -C "${ETC_REPO_ROOT}" submodule update --init --recursive "${module_path}"
        fi
      else
        git -C "${ETC_REPO_ROOT}" submodule update --init --recursive "${module_path}"
      fi
      echo -e "${CHAT_COLOR_GREEN}✓ Initialized ${name}${CHAT_COLOR_RESET}"
    done < <(get_chat_submodules)
    echo -e "${CHAT_COLOR_GREEN}All submodules initialized${CHAT_COLOR_RESET}"
  fi
}

cmd_deinit() {
  local specific_module="${CHAT_SUBMODULE_TARGET-}"

  echo -e "${CHAT_COLOR_BLUE}Deinitializing chat submodules...${CHAT_COLOR_RESET}"

  if [ -n "${specific_module}" ]; then
    local found=false
    while IFS='|' read -r name module_path; do
      if [[ ${name} == "${specific_module}" ]] || [[ ${module_path} == "${specific_module}" ]] || [[ ${module_path} == *"${specific_module}"* ]]; then
        found=true
        if [ -d "${ETC_REPO_ROOT}/${module_path}" ]; then
          echo -e "${CHAT_COLOR_BLUE}Deinitializing ${name} (${module_path})...${CHAT_COLOR_RESET}"
          git -C "${ETC_REPO_ROOT}" submodule deinit -f "${module_path}"
          echo -e "${CHAT_COLOR_GREEN}✓ Deinitialized ${name}${CHAT_COLOR_RESET}"
        else
          echo -e "${CHAT_COLOR_YELLOW}Submodule ${name} is not initialized${CHAT_COLOR_RESET}"
        fi
        break
      fi
    done < <(get_chat_submodules)

    if [ "${found}" = false ]; then
      echo -e "${CHAT_COLOR_RED}Error: Submodule '${specific_module}' not found${CHAT_COLOR_RESET}"
      exit 1
    fi
  else
    while IFS='|' read -r name module_path; do
      if [ -d "${ETC_REPO_ROOT}/${module_path}" ]; then
        echo -e "${CHAT_COLOR_BLUE}Deinitializing ${name} (${module_path})...${CHAT_COLOR_RESET}"
        git -C "${ETC_REPO_ROOT}" submodule deinit -f "${module_path}"
        echo -e "${CHAT_COLOR_GREEN}✓ Deinitialized ${name}${CHAT_COLOR_RESET}"
      else
        echo -e "${CHAT_COLOR_YELLOW}Submodule ${name} is not initialized${CHAT_COLOR_RESET}"
      fi
    done < <(get_chat_submodules)
  fi

  echo -e "${CHAT_COLOR_GREEN}Done${CHAT_COLOR_RESET}"
}

cmd_status() {
  echo -e "${CHAT_COLOR_BLUE}Submodule Status:${CHAT_COLOR_RESET}"

  while IFS='|' read -r name module_path; do
    local info
    info=$(get_submodule_info "${name}" "${module_path}")
    IFS='|' read -r name module_path branch url <<<"${info}"

    if [ -d "${ETC_REPO_ROOT}/${module_path}" ] && ([ -f "${ETC_REPO_ROOT}/${module_path}/.git" ] || [ -d "${ETC_REPO_ROOT}/${module_path}/.git" ]); then
      local current_commit
      current_commit="$(git -C "${ETC_REPO_ROOT}/${module_path}" rev-parse HEAD 2>/dev/null || echo "unknown")"
      local has_changes
      has_changes="$(git -C "${ETC_REPO_ROOT}/${module_path}" status --porcelain 2>/dev/null | wc -l)"

      echo ""
      echo -e "${CHAT_COLOR_BLUE}=== ${name} (${module_path}) ===${CHAT_COLOR_RESET}"
      echo "  URL: ${url}"
      echo "  Tracked branch: ${branch}"
      echo "  Current commit: ${current_commit:0:8}"
      if [ "${has_changes}" -gt 0 ]; then
        echo -e "  Status: ${CHAT_COLOR_YELLOW}⚠️  Has uncommitted changes (${has_changes} files)${CHAT_COLOR_RESET}"
      else
        echo -e "  Status: ${CHAT_COLOR_GREEN}✓ Clean${CHAT_COLOR_RESET}"
      fi
    else
      echo ""
      echo -e "${CHAT_COLOR_BLUE}=== ${name} (${module_path}) ===${CHAT_COLOR_RESET}"
      echo "  URL: ${url}"
      echo "  Tracked branch: ${branch}"
      echo -e "  Status: ${CHAT_COLOR_YELLOW}Not initialized${CHAT_COLOR_RESET}"
    fi
  done < <(get_chat_submodules)

  echo ""
}

cmd_check_updates() {
  local show_commits=true
  if [ "${CHAT_SUBMODULE_BRIEF:-0}" = "1" ]; then
    show_commits=false
  fi

  local has_updates=false

  while IFS='|' read -r name module_path; do
    if [ ! -d "${ETC_REPO_ROOT}/${module_path}" ]; then
      echo -e "${CHAT_COLOR_YELLOW}${name}: ⚠️  Not initialized${CHAT_COLOR_RESET}"
      continue
    fi

    local info
    info=$(get_submodule_info "${name}" "${module_path}")
    IFS='|' read -r name module_path branch url <<<"${info}"

    if [ "${show_commits}" = true ]; then
      echo ""
      echo -e "${CHAT_COLOR_BLUE}=== ${name} (${module_path}) ===${CHAT_COLOR_RESET}"
      echo "Tracked branch: ${branch}"
    fi

    git -C "${ETC_REPO_ROOT}/${module_path}" fetch --depth 10 origin "${branch}" 2>/dev/null || git -C "${ETC_REPO_ROOT}/${module_path}" fetch --depth 10 origin 2>/dev/null
    local behind
    behind="$(git -C "${ETC_REPO_ROOT}/${module_path}" rev-list --count HEAD..origin/"${branch}" 2>/dev/null || git -C "${ETC_REPO_ROOT}/${module_path}" rev-list --count HEAD..origin/HEAD 2>/dev/null || echo "0")"

    if [ "${behind}" -gt 0 ]; then
      has_updates=true
      echo -e "${name}: ${CHAT_COLOR_YELLOW}⚠️  ${behind} new commit(s) available${CHAT_COLOR_RESET}"
      if [ "${show_commits}" = true ]; then
        echo ""
        echo "New commits:"
        git -C "${ETC_REPO_ROOT}/${module_path}" --no-pager log HEAD..origin/"${branch}" --oneline 2>/dev/null || git -C "${ETC_REPO_ROOT}/${module_path}" --no-pager log HEAD..origin/HEAD --oneline 2>/dev/null
      fi
    else
      echo -e "${name}: ${CHAT_COLOR_GREEN}✅ up to date${CHAT_COLOR_RESET}"
    fi
  done < <(get_chat_submodules)

  echo ""
  if [ "${has_updates}" = true ]; then
    echo -e "${CHAT_COLOR_YELLOW}Some submodules have updates available. Use the update step to update them.${CHAT_COLOR_RESET}"
  fi
}

cmd_update() {
  local specific_module="${CHAT_SUBMODULE_TARGET-}"

  echo -e "${CHAT_COLOR_BLUE}Updating chat submodules...${CHAT_COLOR_RESET}"

  if [ -n "${specific_module}" ]; then
    local found=false
    while IFS='|' read -r name module_path; do
      if [[ ${name} == "${specific_module}" ]] || [[ ${module_path} == "${specific_module}" ]] || [[ ${module_path} == *"${specific_module}"* ]]; then
        found=true
        if [ ! -d "${ETC_REPO_ROOT}/${module_path}" ]; then
          echo -e "${CHAT_COLOR_YELLOW}Submodule ${name} is not initialized. Initializing first...${CHAT_COLOR_RESET}"
          git -C "${ETC_REPO_ROOT}" submodule update --init --recursive "${module_path}"
        fi

        local info
        info=$(get_submodule_info "${name}" "${module_path}")
        IFS='|' read -r name module_path branch url <<<"${info}"

        echo -e "${CHAT_COLOR_BLUE}Updating ${name} (${module_path}) to latest on ${branch}...${CHAT_COLOR_RESET}"
        git -C "${ETC_REPO_ROOT}/${module_path}" fetch --depth 10 origin "${branch}" 2>/dev/null || git -C "${ETC_REPO_ROOT}/${module_path}" fetch --depth 10 origin 2>/dev/null
        git -C "${ETC_REPO_ROOT}/${module_path}" checkout "${branch}" 2>/dev/null || git -C "${ETC_REPO_ROOT}/${module_path}" checkout -b "${branch}" "origin/${branch}" 2>/dev/null || true
        git -C "${ETC_REPO_ROOT}/${module_path}" pull origin "${branch}" 2>/dev/null || git -C "${ETC_REPO_ROOT}/${module_path}" merge "origin/${branch}" 2>/dev/null || true
        local new_commit
        new_commit="$(git -C "${ETC_REPO_ROOT}/${module_path}" rev-parse HEAD 2>/dev/null || echo "unknown")"
        echo -e "${CHAT_COLOR_GREEN}✓ Updated ${name} to ${new_commit:0:8}${CHAT_COLOR_RESET}"
        break
      fi
    done < <(get_chat_submodules)

    if [ "${found}" = false ]; then
      echo -e "${CHAT_COLOR_RED}Error: Submodule '${specific_module}' not found${CHAT_COLOR_RESET}"
      exit 1
    fi
  else
    while IFS='|' read -r name module_path; do
      if [ ! -d "${ETC_REPO_ROOT}/${module_path}" ]; then
        echo -e "${CHAT_COLOR_YELLOW}Submodule ${name} is not initialized. Initializing first...${CHAT_COLOR_RESET}"
        git -C "${ETC_REPO_ROOT}" submodule update --init --recursive "${module_path}"
      fi

      local info
      info=$(get_submodule_info "${name}" "${module_path}")
      IFS='|' read -r name module_path branch url <<<"${info}"

      echo -e "${CHAT_COLOR_BLUE}Updating ${name} (${module_path}) to latest on ${branch}...${CHAT_COLOR_RESET}"
      git -C "${ETC_REPO_ROOT}/${module_path}" fetch --depth 10 origin "${branch}" 2>/dev/null || git -C "${ETC_REPO_ROOT}/${module_path}" fetch --depth 10 origin 2>/dev/null
      git -C "${ETC_REPO_ROOT}/${module_path}" checkout "${branch}" 2>/dev/null || git -C "${ETC_REPO_ROOT}/${module_path}" checkout -b "${branch}" "origin/${branch}" 2>/dev/null || true
      git -C "${ETC_REPO_ROOT}/${module_path}" pull origin "${branch}" 2>/dev/null || git -C "${ETC_REPO_ROOT}/${module_path}" merge "origin/${branch}" 2>/dev/null || true
      local new_commit
      new_commit="$(git -C "${ETC_REPO_ROOT}/${module_path}" rev-parse HEAD 2>/dev/null || echo "unknown")"
      echo -e "${CHAT_COLOR_GREEN}✓ Updated ${name} to ${new_commit:0:8}${CHAT_COLOR_RESET}"
    done < <(get_chat_submodules)
    echo -e "${CHAT_COLOR_GREEN}All submodules updated${CHAT_COLOR_RESET}"
  fi
}
